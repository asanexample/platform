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

package main

import (
	"context"
	"crypto/tls"
	"flag"
	"os"
	"strings"
	"time"

	// Import all Kubernetes client auth plugins (e.g. Azure, GCP, OIDC, etc.)
	// to ensure that exec-entrypoint and run can make use of them.
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/metrics/filters"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
	"sigs.k8s.io/controller-runtime/pkg/webhook"

	platformv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
	platformv1beta1 "github.com/asanexample/platform/operators/activation/api/v1beta1"
	"github.com/asanexample/platform/operators/activation/internal/catalog"
	"github.com/asanexample/platform/operators/activation/internal/controller"
	"github.com/asanexample/platform/operators/activation/internal/eligibility"
	"github.com/asanexample/platform/operators/activation/internal/plane/awsidc"
	"github.com/asanexample/platform/operators/activation/internal/telemetry"
	// +kubebuilder:scaffold:imports
)

// version is the operator build version, stamped via -ldflags at build time.
var version = "dev"

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))

	utilruntime.Must(platformv1alpha1.AddToScheme(scheme))
	utilruntime.Must(platformv1beta1.AddToScheme(scheme))
	// +kubebuilder:scaffold:scheme
}

// nolint:gocyclo
func main() {
	var metricsAddr string
	var metricsCertPath, metricsCertName, metricsCertKey string
	var webhookCertPath, webhookCertName, webhookCertKey string
	var enableLeaderElection bool
	var probeAddr string
	var secureMetrics bool
	var enableHTTP2 bool
	var awsRegion string
	var identityCenterRoleArn string
	var excludeAccountIDs string
	var syncPeriod time.Duration
	var tlsOpts []func(*tls.Config)
	flag.StringVar(&awsRegion, "aws-region", "us-east-1", "AWS region of the Identity Center instance.")
	flag.StringVar(&identityCenterRoleArn, "identity-center-role-arn", "",
		"Management-account IAM role the operator assumes to reach the Identity Center sso-admin plane "+
			"(cross-account). Empty uses the pod's own credentials directly.")
	flag.StringVar(&excludeAccountIDs, "exclude-account-ids", "",
		"Comma-separated AWS account IDs the operator must NEVER assign in, even when a permission set is "+
			"provisioned to them (a blast-radius guard — e.g. the org-root management account stays a manual path).")
	flag.DurationVar(&syncPeriod, "sync-period", 2*time.Minute,
		"Cache resync period — the safety net that re-reconciles every Activation so a dropped expiry "+
			"timer self-heals while the drift backstop is deferred.")
	flag.StringVar(&metricsAddr, "metrics-bind-address", "0", "The address the metrics endpoint binds to. "+
		"Use :8443 for HTTPS or :8080 for HTTP, or leave as 0 to disable the metrics service.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "The address the probe endpoint binds to.")
	flag.BoolVar(&enableLeaderElection, "leader-elect", false,
		"Enable leader election for controller manager. "+
			"Enabling this will ensure there is only one active controller manager.")
	flag.BoolVar(&secureMetrics, "metrics-secure", true,
		"If set, the metrics endpoint is served securely via HTTPS. Use --metrics-secure=false to use HTTP instead.")
	flag.StringVar(&webhookCertPath, "webhook-cert-path", "", "The directory that contains the webhook certificate.")
	flag.StringVar(&webhookCertName, "webhook-cert-name", "tls.crt", "The name of the webhook certificate file.")
	flag.StringVar(&webhookCertKey, "webhook-cert-key", "tls.key", "The name of the webhook key file.")
	flag.StringVar(&metricsCertPath, "metrics-cert-path", "",
		"The directory that contains the metrics server certificate.")
	flag.StringVar(&metricsCertName, "metrics-cert-name", "tls.crt", "The name of the metrics server certificate file.")
	flag.StringVar(&metricsCertKey, "metrics-cert-key", "tls.key", "The name of the metrics server key file.")
	flag.BoolVar(&enableHTTP2, "enable-http2", false,
		"If set, HTTP/2 will be enabled for the metrics and webhook servers")
	opts := zap.Options{
		Development: true,
	}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	rootCtx := ctrl.SetupSignalHandler()

	// Unified OpenTelemetry pipeline (traces + metrics over OTLP to the collector). No-op when
	// OTEL_EXPORTER_OTLP_ENDPOINT is unset, so local runs work without a collector.
	telem, err := telemetry.Setup(rootCtx, "activation-operator", version)
	if err != nil {
		setupLog.Error(err, "Failed to set up telemetry")
		os.Exit(1)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := telem.Shutdown(shutdownCtx); err != nil {
			setupLog.Error(err, "telemetry shutdown")
		}
	}()

	// if the enable-http2 flag is false (the default), http/2 should be disabled
	// due to its vulnerabilities. More specifically, disabling http/2 will
	// prevent from being vulnerable to the HTTP/2 Stream Cancellation and
	// Rapid Reset CVEs. For more information see:
	// - https://github.com/advisories/GHSA-qppj-fm5r-hxr3
	// - https://github.com/advisories/GHSA-4374-p667-p6c8
	disableHTTP2 := func(c *tls.Config) {
		setupLog.Info("Disabling HTTP/2")
		c.NextProtos = []string{"http/1.1"}
	}

	if !enableHTTP2 {
		tlsOpts = append(tlsOpts, disableHTTP2)
	}

	// Initial webhook TLS options
	webhookTLSOpts := tlsOpts
	webhookServerOptions := webhook.Options{
		TLSOpts: webhookTLSOpts,
	}

	if len(webhookCertPath) > 0 {
		setupLog.Info("Initializing webhook certificate watcher using provided certificates",
			"webhook-cert-path", webhookCertPath, "webhook-cert-name", webhookCertName, "webhook-cert-key", webhookCertKey)

		webhookServerOptions.CertDir = webhookCertPath
		webhookServerOptions.CertName = webhookCertName
		webhookServerOptions.KeyName = webhookCertKey
	}

	webhookServer := webhook.NewServer(webhookServerOptions)

	// Metrics endpoint is enabled in 'config/default/kustomization.yaml'. The Metrics options configure the server.
	// More info:
	// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.23.3/pkg/metrics/server
	// - https://book.kubebuilder.io/reference/metrics.html
	metricsServerOptions := metricsserver.Options{
		BindAddress:   metricsAddr,
		SecureServing: secureMetrics,
		TLSOpts:       tlsOpts,
	}

	if secureMetrics {
		// FilterProvider is used to protect the metrics endpoint with authn/authz.
		// These configurations ensure that only authorized users and service accounts
		// can access the metrics endpoint. The RBAC are configured in 'config/rbac/kustomization.yaml'. More info:
		// https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.23.3/pkg/metrics/filters#WithAuthenticationAndAuthorization
		metricsServerOptions.FilterProvider = filters.WithAuthenticationAndAuthorization
	}

	// If the certificate is not specified, controller-runtime will automatically
	// generate self-signed certificates for the metrics server. While convenient for development and testing,
	// this setup is not recommended for production.
	//
	// TODO(user): If you enable certManager, uncomment the following lines:
	// - [METRICS-WITH-CERTS] at config/default/kustomization.yaml to generate and use certificates
	// managed by cert-manager for the metrics server.
	// - [PROMETHEUS-WITH-CERTS] at config/prometheus/kustomization.yaml for TLS certification.
	if len(metricsCertPath) > 0 {
		setupLog.Info("Initializing metrics certificate watcher using provided certificates",
			"metrics-cert-path", metricsCertPath, "metrics-cert-name", metricsCertName, "metrics-cert-key", metricsCertKey)

		metricsServerOptions.CertDir = metricsCertPath
		metricsServerOptions.CertName = metricsCertName
		metricsServerOptions.KeyName = metricsCertKey
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsServerOptions,
		WebhookServer:          webhookServer,
		HealthProbeBindAddress: probeAddr,
		Cache:                  cache.Options{SyncPeriod: &syncPeriod},
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "0a69d8b8.refplat.org",
		// LeaderElectionReleaseOnCancel defines if the leader should step down voluntarily
		// when the Manager ends. This requires the binary to immediately end when the
		// Manager is stopped, otherwise, this setting is unsafe. Setting this significantly
		// speeds up voluntary leader transitions as the new leader don't have to wait
		// LeaseDuration time first.
		//
		// In the default scaffold provided, the program ends immediately after
		// the manager stops, so would be fine to enable this option. However,
		// if you are doing or is intended to do any operation such as perform cleanups
		// after the manager stops then its usage might be unsafe.
		// LeaderElectionReleaseOnCancel: true,
	})
	if err != nil {
		setupLog.Error(err, "Failed to start manager")
		os.Exit(1)
	}

	// The role catalog (in-cluster WorkforceRole CRs) backs both the borrow cap and the
	// permission-set resolution, replacing the bootstrap --role-permission-sets flag.
	roleCatalog := catalog.New(mgr.GetClient())
	resolvePS := func(ctx context.Context, role string) (string, error) {
		info, err := roleCatalog.Lookup(ctx, role)
		if err != nil {
			return "", err
		}
		return info.PermissionSet, nil
	}

	// The AWS Identity Center plane (live SDK client), resolving role→permission-set from the catalog.
	awsClient, err := awsidc.NewClient(rootCtx, awsRegion, identityCenterRoleArn)
	if err != nil {
		setupLog.Error(err, "Failed to build AWS Identity Center client")
		os.Exit(1)
	}
	var excludeAccounts []string
	for id := range strings.SplitSeq(excludeAccountIDs, ",") {
		if id = strings.TrimSpace(id); id != "" {
			excludeAccounts = append(excludeAccounts, id)
		}
	}
	awsPlane := awsidc.New(awsClient, resolvePS, excludeAccounts...)

	if err := (&controller.ActivationReconciler{
		Client:      mgr.GetClient(),
		Scheme:      mgr.GetScheme(),
		Plane:       awsPlane,
		Catalog:     roleCatalog,
		Eligibility: eligibility.New(mgr.GetClient()),
		Telemetry:   telem,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "Failed to create controller", "controller", "Activation")
		os.Exit(1)
	}
	// +kubebuilder:scaffold:builder

	// Restart-safe observable gauges (active + leaked), recomputed from cluster state on every
	// metric read by listing Activations — never tracked incrementally in memory.
	if err := telem.Metrics.RegisterObservers(func(ctx context.Context) (telemetry.Population, error) {
		var list platformv1alpha1.ActivationList
		if err := mgr.GetClient().List(ctx, &list); err != nil {
			return telemetry.Population{}, err
		}
		pop := telemetry.Population{ActiveByRole: map[string]int64{}}
		now := time.Now()
		for i := range list.Items {
			act := &list.Items[i]
			if act.Status.Phase == platformv1alpha1.PhaseActive {
				pop.ActiveByRole[act.Spec.Role]++
			}
			// Leaked = past expiry but not yet fully torn down (status proxy; the AWS-truth
			// check lands with the drift backstop).
			if act.Status.ExpiresAt != nil && now.After(act.Status.ExpiresAt.Time) &&
				act.Status.Phase != platformv1alpha1.PhaseExpired &&
				act.Status.Phase != platformv1alpha1.PhaseRevoked &&
				act.Status.Phase != platformv1alpha1.PhaseFailed {
				pop.Leaked++
			}
		}
		return pop, nil
	}); err != nil {
		setupLog.Error(err, "Failed to register activation gauges")
		os.Exit(1)
	}

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "Failed to set up health check")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "Failed to set up ready check")
		os.Exit(1)
	}

	setupLog.Info("Starting manager")
	if err := mgr.Start(rootCtx); err != nil {
		setupLog.Error(err, "Failed to run manager")
		os.Exit(1)
	}
}
