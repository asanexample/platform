// Command server is app-${{ values.team }}-${{ values.product }}: a generic starter service for the platform.
//
// It is deliberately minimal — a stdlib-only HTTP server exposing the liveness/readiness endpoint the
// platform deployment manifests probe (/healthz) and a JSON root handler. There is NO cloud/AWS
// dependency: an environment's AWS access (if any) is granted out-of-band via EKS Pod Identity to the named
// ServiceAccount (see k8s/preprod/serviceaccount.yaml) and declared in the Environment claim's `aws` block.
// Add an SDK + the access only when an app actually needs it.
//
// To start a NEW app from this template: copy the repo, rename app-${{ values.team }}-${{ values.product }} -> app-<yourapp>, set your
// team/namespace/hostname in k8s/preprod/, and keep the thin .github/workflows callers as-is.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// newMux wires the routes — extracted so the unit test can exercise them without binding a port.
func newMux(version, namespace string) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
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

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      newMux(version, namespace),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	// Serve in the background; block on SIGTERM/SIGINT (k8s sends SIGTERM on pod termination), then drain
	// in-flight requests gracefully before exiting.
	go func() {
		log.Printf("starting app-${{ values.team }}-${{ values.product }} version=%s namespace=%s", version, namespace)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	log.Println("shutting down (draining in-flight requests)…")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("graceful shutdown failed: %v", err)
	}
	log.Println("stopped")
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
