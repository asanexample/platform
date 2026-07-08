// Command tenant-proxy is the P13 per-team read isolation front door (ADR-043/044, #590).
//
// It sits in front of a multi-tenant store's query API (Mimir/Loki/Tempo). For each request it
// verifies the Grafana-forwarded OIDC token (X-Id-Token), resolves the caller's readable tenant
// scope from their groups, stamps X-Scope-OrgID, and reverse-proxies upstream. It is fail-closed:
// unauthenticated or unscoped requests are rejected before reaching the store.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/asanexample/platform/services/tenant-proxy/internal/auth"
	"github.com/asanexample/platform/services/tenant-proxy/internal/config"
	"github.com/asanexample/platform/services/tenant-proxy/internal/proxy"
	"github.com/asanexample/platform/services/tenant-proxy/internal/tenant"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if err := run(log); err != nil {
		log.Error("fatal", slog.String("err", err.Error()))
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	verifier, err := auth.NewOIDCVerifier(ctx, auth.Config{
		JWKSURL:  cfg.JWKSURL,
		Issuer:   cfg.Issuer,
		Audience: cfg.Audience,
	})
	if err != nil {
		return err
	}

	resolver, err := tenant.NewResolver(cfg.Tenants, cfg.AdminGroup, cfg.Grants)
	if err != nil {
		return err
	}

	metrics := newMetrics()
	upstream := newReverseProxy(cfg, log)
	handler := proxy.New(verifier, resolver, upstream, metrics, log)

	log.Info("starting tenant-proxy",
		slog.String("listen", cfg.ListenAddr),
		slog.String("metrics", cfg.MetricsAddr),
		slog.String("upstream", cfg.UpstreamURL.String()),
		slog.String("issuer", cfg.Issuer),
		slog.String("resolver", resolver.String()))

	proxySrv := &http.Server{Addr: cfg.ListenAddr, Handler: handler, ReadHeaderTimeout: 10 * time.Second}
	metricsSrv := &http.Server{Addr: cfg.MetricsAddr, Handler: metricsMux(), ReadHeaderTimeout: 10 * time.Second}

	errCh := make(chan error, 2)
	go serve(proxySrv, errCh)
	go serve(metricsSrv, errCh)

	select {
	case <-ctx.Done():
		log.Info("shutdown signal received")
	case err := <-errCh:
		if err != nil {
			return err
		}
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = proxySrv.Shutdown(shutdownCtx)
	_ = metricsSrv.Shutdown(shutdownCtx)
	return nil
}

func serve(s *http.Server, errCh chan<- error) {
	if err := s.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		errCh <- err
	}
}

// newReverseProxy builds the upstream reverse proxy. NewSingleHostReverseProxy joins the upstream
// base path (…/prometheus) with the request path (/api/v1/query), which is exactly the store's API
// layout. A failing upstream returns 502 rather than a panic.
func newReverseProxy(cfg *config.Config, log *slog.Logger) http.Handler {
	rp := httputil.NewSingleHostReverseProxy(cfg.UpstreamURL)
	rp.Transport = &http.Transport{
		ResponseHeaderTimeout: cfg.UpstreamTimeout,
		IdleConnTimeout:       90 * time.Second,
	}
	rp.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, err error) {
		log.Error("upstream error", slog.String("err", err.Error()))
		http.Error(w, "upstream unavailable", http.StatusBadGateway)
	}
	return rp
}

// promMetrics implements proxy.Metrics with a single labeled counter.
type promMetrics struct {
	requests *prometheus.CounterVec
}

func newMetrics() *promMetrics {
	return &promMetrics{
		requests: promauto.NewCounterVec(prometheus.CounterOpts{
			Name: "tenant_proxy_requests_total",
			Help: "Tenant-proxy request decisions by result (allowed or a deny reason).",
		}, []string{"result"}),
	}
}

func (m *promMetrics) Allowed()             { m.requests.WithLabelValues("allowed").Inc() }
func (m *promMetrics) Denied(reason string) { m.requests.WithLabelValues(reason).Inc() }

func metricsMux() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	return mux
}
