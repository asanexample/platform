/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Package telemetry wires the activation operator's unified OpenTelemetry pipeline: traces
// and metrics export over OTLP to the cluster otel-collector (→ Tempo / Mimir), correlated
// with the structured logs the controller-runtime logger emits to stdout (→ Loki). This is
// the access-governance audit surface (ADR-088 §3.6), not just ops telemetry.
//
// If no OTLP endpoint is configured (OTEL_EXPORTER_OTLP_ENDPOINT unset), Setup installs
// no-op providers so local runs and tests work without a collector.
package telemetry

import (
	"context"
	"fmt"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

const scopeName = "github.com/asanexample/platform/operators/activation"

// Telemetry holds the operator's tracer and the domain metric instruments. It is created
// once at startup and shared with the reconciler.
type Telemetry struct {
	Tracer  trace.Tracer
	Metrics *Metrics

	shutdownFns []func(context.Context) error
}

// Metrics are the activation operator's domain instruments. Framework metrics (reconcile
// latency, queue depth) come from controller-runtime; these are the access-governance signals.
type Metrics struct {
	meter metric.Meter

	// MintDuration / RevokeDuration record the wall time to fully grant / fully revoke a borrow.
	MintDuration   metric.Float64Histogram
	RevokeDuration metric.Float64Histogram
	// MintFailures / RevokeFailures count terminal failures, labeled by plane and error kind.
	MintFailures   metric.Int64Counter
	RevokeFailures metric.Int64Counter
}

// Setup builds the OTLP trace+metric providers (or no-ops when no endpoint is set), installs
// them as the global providers, and returns the Telemetry handle. Call Shutdown to flush.
func Setup(ctx context.Context, serviceName, serviceVersion string) (*Telemetry, error) {
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion(serviceVersion),
		),
		resource.WithFromEnv(),
		resource.WithProcess(),
	)
	if err != nil {
		return nil, fmt.Errorf("building otel resource: %w", err)
	}

	t := &Telemetry{}
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")

	// Tracing.
	if endpoint != "" {
		exp, err := otlptracegrpc.New(ctx)
		if err != nil {
			return nil, fmt.Errorf("otlp trace exporter: %w", err)
		}
		tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exp), sdktrace.WithResource(res))
		otel.SetTracerProvider(tp)
		t.shutdownFns = append(t.shutdownFns, tp.Shutdown)
	}
	t.Tracer = otel.Tracer(scopeName)

	// Metrics.
	if endpoint != "" {
		mexp, err := otlpmetricgrpc.New(ctx)
		if err != nil {
			return nil, fmt.Errorf("otlp metric exporter: %w", err)
		}
		mp := sdkmetric.NewMeterProvider(
			sdkmetric.WithReader(sdkmetric.NewPeriodicReader(mexp)),
			sdkmetric.WithResource(res),
		)
		otel.SetMeterProvider(mp)
		t.shutdownFns = append(t.shutdownFns, mp.Shutdown)
	}

	m, err := newMetrics(otel.Meter(scopeName))
	if err != nil {
		return nil, err
	}
	t.Metrics = m
	return t, nil
}

// Shutdown flushes and stops the providers, in reverse order of registration.
func (t *Telemetry) Shutdown(ctx context.Context) error {
	var firstErr error
	for i := len(t.shutdownFns) - 1; i >= 0; i-- {
		if err := t.shutdownFns[i](ctx); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func newMetrics(meter metric.Meter) (*Metrics, error) {
	m := &Metrics{meter: meter}
	var err error
	// Instrument names follow OTel convention (no unit, no _total suffix) — the Prometheus
	// exporter appends "_seconds" for the unit and "_total" for monotonic counters, giving
	// activation_mint_duration_seconds and activation_mint_failures_total in Mimir.
	if m.MintDuration, err = meter.Float64Histogram(
		"activation_mint_duration",
		metric.WithDescription("Wall time to fully grant a borrowed power across all accounts."),
		metric.WithUnit("s"),
	); err != nil {
		return nil, err
	}
	if m.RevokeDuration, err = meter.Float64Histogram(
		"activation_revoke_duration",
		metric.WithDescription("Wall time to fully revoke a borrowed power across all accounts."),
		metric.WithUnit("s"),
	); err != nil {
		return nil, err
	}
	if m.MintFailures, err = meter.Int64Counter(
		"activation_mint_failures",
		metric.WithDescription("Terminal failures while minting a borrowed power."),
	); err != nil {
		return nil, err
	}
	if m.RevokeFailures, err = meter.Int64Counter(
		"activation_revoke_failures",
		metric.WithDescription("Terminal failures while revoking a borrowed power."),
	); err != nil {
		return nil, err
	}
	return m, nil
}

// ObserveFunc reports the current activation population for the observable gauges. It is
// supplied by the controller (which can list Activations) so the gauges are restart-safe —
// recomputed from cluster state on every collection, never tracked incrementally in memory.
type ObserveFunc func(ctx context.Context) (Population, error)

// Population is the current count of activations by lifecycle, plus the leaked count — the
// single most important governance signal (live past expiry; the controller's expiry is the
// only backstop until the drift detector lands).
type Population struct {
	ActiveByRole map[string]int64
	Leaked       int64
}

// RegisterObservers installs the active-grant and leaked-grant observable gauges, collected
// via observe on every metric read. Restart-safe (recomputed from cluster state each time).
func (m *Metrics) RegisterObservers(observe ObserveFunc) error {
	active, err := m.meter.Int64ObservableGauge(
		"activation_active",
		metric.WithDescription("Currently active borrowed powers, by role."),
	)
	if err != nil {
		return err
	}
	leaked, err := m.meter.Int64ObservableGauge(
		"activation_leaked",
		metric.WithDescription("Borrows live in AWS past their expiry — a leaked master key. Should always be 0."),
	)
	if err != nil {
		return err
	}
	_, err = m.meter.RegisterCallback(
		func(ctx context.Context, o metric.Observer) error {
			pop, err := observe(ctx)
			if err != nil {
				return err
			}
			for role, n := range pop.ActiveByRole {
				o.ObserveInt64(active, n, metric.WithAttributes(attribute.String("role", role)))
			}
			o.ObserveInt64(leaked, pop.Leaked)
			return nil
		},
		active, leaked,
	)
	return err
}
