// Command server is app-${{ values.team }}-${{ values.product }}: a generic starter service for the platform.
//
// It is a stdlib-only HTTP server exposing the liveness/readiness endpoint the platform deployment manifests
// probe (/healthz) and a JSON root handler. There is NO cloud/AWS dependency: an environment's AWS access (if
// any) is granted out-of-band via EKS Pod Identity to the named ServiceAccount and declared in the Environment
// claim's `aws` block. Add the access only when an app actually needs it.
//
// OBSERVABILITY (ADR-077 Layer 1 / P14) — wired by construction: the server runs the OpenTelemetry SDK so every
// request opens a server span, exporting to the platform OTLP collector (OTEL_EXPORTER_OTLP_ENDPOINT, injected
// by the manifest). Logs are structured JSON via slog, and a handler stamps the active span's `trace_id`/
// `span_id` onto every line — so a log in Loki links straight to its trace in Tempo (the Loki derived field
// keys on `trace_id`). This is the app-level correlation Beyla (eBPF) can't provide (it never sees app stdout).
// When you add an outbound HTTP call, wrap the client's Transport with otelhttp.NewTransport to propagate the
// trace to the downstream service.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

// logger is initialized at package scope so newMux handlers are safe to call in tests (which don't run
// main()). main() additionally sets it as slog's default.
var logger = slog.New(traceHandler{slog.NewJSONHandler(os.Stdout, nil)})

// traceHandler wraps a slog.Handler and stamps the active span's trace/span IDs onto each record, so every
// log line carries the `trace_id` the Loki→Tempo derived field links on. A no-op when there's no active span.
type traceHandler struct{ slog.Handler }

func (h traceHandler) Handle(ctx context.Context, r slog.Record) error {
	if sc := trace.SpanContextFromContext(ctx); sc.IsValid() {
		r.AddAttrs(
			slog.String("trace_id", sc.TraceID().String()),
			slog.String("span_id", sc.SpanID().String()),
		)
	}
	return h.Handler.Handle(ctx, r)
}

// newMux wires the routes — extracted so the unit test can exercise them without binding a port.
func newMux(version, namespace string) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		// A per-request log carrying trace_id — the line you click in Loki to jump to the trace.
		logger.InfoContext(r.Context(), "handled request", "path", r.URL.Path, "host", r.Host)
		writeJSON(w, http.StatusOK, map[string]string{
			"app":       "app-${{ values.team }}-${{ values.product }}",
			"version":   version,
			"namespace": namespace,
			"hostname":  r.Host,
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	})

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	return mux
}

func main() {
	version := getenv("VERSION", "dev")
	namespace := getenv("NAMESPACE", "unknown")

	slog.SetDefault(logger)

	// OpenTelemetry: OTLP/HTTP trace export to the platform collector (endpoint from the injected env, never
	// hardcoded). Degrades cleanly if OTEL_EXPORTER_OTLP_ENDPOINT is unset (local runs).
	shutdown, err := initTracer(context.Background())
	if err != nil {
		logger.Error("otel init failed; continuing without tracing", "err", err)
	} else {
		defer func() { _ = shutdown(context.Background()) }()
	}

	// otelhttp opens a server span per request (and puts the trace in the request context the handlers log
	// with). "http.server" is the span-name formatter root.
	handler := otelhttp.NewHandler(newMux(version, namespace), "http.server")

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      handler,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	// Serve in the background; block on SIGTERM/SIGINT (k8s sends SIGTERM on pod termination), then drain
	// in-flight requests gracefully before exiting.
	go func() {
		logger.Info("starting app-${{ values.team }}-${{ values.product }}", "version", version, "namespace", namespace)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	logger.Info("shutting down (draining in-flight requests)…")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("graceful shutdown failed", "err", err)
		os.Exit(1)
	}
	logger.Info("stopped")
}

// initTracer sets up the global tracer provider + W3C propagator with an OTLP/HTTP exporter. Returns a
// shutdown func that flushes the batch processor. If OTEL_EXPORTER_OTLP_ENDPOINT is unset the exporter still
// constructs (defaults to localhost) but export failures are silent — fine for local/test runs.
func initTracer(ctx context.Context) (func(context.Context) error, error) {
	exp, err := otlptracehttp.New(ctx)
	if err != nil {
		return nil, fmt.Errorf("otlp exporter: %w", err)
	}
	res, err := resource.New(ctx,
		resource.WithFromEnv(), // OTEL_SERVICE_NAME / OTEL_RESOURCE_ATTRIBUTES
		resource.WithAttributes(semconv.ServiceName(getenv("OTEL_SERVICE_NAME", "app-${{ values.team }}-${{ values.product }}"))),
	)
	if err != nil {
		return nil, fmt.Errorf("otel resource: %w", err)
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))
	return tp.Shutdown, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
