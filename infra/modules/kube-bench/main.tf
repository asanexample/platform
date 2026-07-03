locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123).
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  app_labels = merge(local.k8s_labels, { "app.kubernetes.io/name" = "kube-bench" })

  # kube-bench run args. JSON to stdout (in addition to the summary) so a log pipeline can parse per-check
  # results; the human-readable summary is always logged.
  scan_args = concat(
    ["run", "--benchmark", var.benchmark, "--targets", var.targets],
    var.json_output ? ["--json"] : [],
  )
}

# ---------------------------------------------------------------------------
# Namespace — dedicated, privileged PSA so the read-only host-mount + hostPID scan pod is admitted.
# Carries no platform.refplat.org/team label, so it is NOT an environment namespace and the
# environment-scoped Kyverno policies (image/probe/registry/etc.) do not apply — same as falco.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "kube_bench" {
  count = local.create ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(local.k8s_labels, {
      "app.kubernetes.io/name" = "kube-bench"
      # This scan legitimately needs hostPID + read-only host mounts to inspect node/kubelet config.
      # Pin the namespace to the privileged Pod Security Standard so a cluster-wide baseline default
      # (if any) can't reject it.
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    })
  }
}

# ---------------------------------------------------------------------------
# ServiceAccount + read-only RBAC — the 'policies' target lists in-cluster RBAC / NetworkPolicy objects.
# Least privilege: get/list/watch only, on the specific resource kinds kube-bench inspects. No wildcards,
# no write verbs — the scan never mutates the cluster.
# ---------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "kube_bench" {
  count = local.create ? 1 : 0

  metadata {
    name      = "kube-bench"
    namespace = kubernetes_namespace_v1.kube_bench[0].metadata[0].name
    labels    = local.app_labels
  }
}

resource "kubernetes_cluster_role_v1" "kube_bench" {
  count = local.create ? 1 : 0

  metadata {
    name   = "kube-bench-scan-readonly"
    labels = local.app_labels
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "nodes", "pods", "serviceaccounts", "services", "resourcequotas", "limitranges"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "kube_bench" {
  count = local.create ? 1 : 0

  metadata {
    name   = "kube-bench-scan-readonly"
    labels = local.app_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.kube_bench[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.kube_bench[0].metadata[0].name
    namespace = kubernetes_namespace_v1.kube_bench[0].metadata[0].name
  }
}

# ---------------------------------------------------------------------------
# kube-bench CronJob — runs the CIS EKS Benchmark read-only on a schedule and prints findings to stdout
# (picked up by the log pipeline). Reads node/kubelet config via read-only hostPath mounts + hostPID;
# never writes to the host or the cluster. Root filesystem is read-only (an emptyDir backs /tmp).
# ---------------------------------------------------------------------------

resource "kubernetes_cron_job_v1" "kube_bench" {
  count = local.create ? 1 : 0

  metadata {
    name      = "kube-bench"
    namespace = kubernetes_namespace_v1.kube_bench[0].metadata[0].name
    labels    = local.app_labels
  }

  spec {
    schedule                      = var.schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = var.successful_jobs_history_limit
    failed_jobs_history_limit     = var.failed_jobs_history_limit

    job_template {
      metadata {
        labels = local.app_labels
      }
      spec {
        backoff_limit              = 0
        ttl_seconds_after_finished = var.ttl_seconds_after_finished

        template {
          metadata {
            labels = local.app_labels
          }
          spec {
            service_account_name = kubernetes_service_account_v1.kube_bench[0].metadata[0].name
            restart_policy       = "Never"
            # Needed for the 'node' target — inspecting kubelet process/command-line CIS checks.
            host_pid      = true
            node_selector = var.node_selector

            dynamic "toleration" {
              for_each = var.tolerations
              content {
                key      = toleration.value.key
                operator = toleration.value.operator
                value    = toleration.value.value
                effect   = toleration.value.effect
              }
            }

            container {
              name    = "kube-bench"
              image   = var.image
              command = ["kube-bench"]
              args    = local.scan_args

              security_context {
                # kube-bench reads root-owned host config files, so it runs as root — but with no
                # privilege escalation, all capabilities dropped, and a read-only root filesystem.
                # This is host-config *reading*, not a privileged container.
                run_as_user                = 0
                allow_privilege_escalation = false
                read_only_root_filesystem  = true

                capabilities {
                  drop = ["ALL"]
                }

                seccomp_profile {
                  type = "RuntimeDefault"
                }
              }

              # Read-only views of the host paths the CIS node checks inspect.
              volume_mount {
                name       = "var-lib-kubelet"
                mount_path = "/var/lib/kubelet"
                read_only  = true
              }
              volume_mount {
                name       = "etc-systemd"
                mount_path = "/etc/systemd"
                read_only  = true
              }
              volume_mount {
                name       = "etc-kubernetes"
                mount_path = "/etc/kubernetes"
                read_only  = true
              }
              # Writable scratch so the root filesystem can stay read-only.
              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
                read_only  = false
              }

              resources {
                requests = var.resources.requests
                limits   = var.resources.limits
              }
            }

            volume {
              name = "var-lib-kubelet"
              host_path {
                path = "/var/lib/kubelet"
                type = "Directory"
              }
            }
            volume {
              name = "etc-systemd"
              host_path {
                path = "/etc/systemd"
                type = "Directory"
              }
            }
            volume {
              name = "etc-kubernetes"
              host_path {
                path = "/etc/kubernetes"
                type = "Directory"
              }
            }
            volume {
              name = "tmp"
              empty_dir {}
            }
          }
        }
      }
    }
  }
}
