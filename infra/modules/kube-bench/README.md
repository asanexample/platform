# kube-bench

Runs **[kube-bench](https://github.com/aquasecurity/kube-bench)** — the **CIS Kubernetes/EKS Benchmark**
scanner — as a scheduled, **read-only** posture scan on the cluster (the *scan* half of #1149; node/AMI
hardening is tracked separately). It mirrors the `falco` module's shape: a dedicated privileged namespace
for a cluster-security tool that legitimately needs host access, kept out of tenant/PSA-restricted
namespaces.

## What it deploys

- A dedicated **`kube-bench` namespace**, labelled `pod-security.kubernetes.io/*: privileged` (the scan
  needs `hostPID` + read-only host mounts). It carries **no** `platform.refplat.org/team` label, so it is
  not an environment namespace and the environment-scoped Kyverno policies do not apply.
- A **CronJob** (`kube-bench`, default `0 6 * * *` UTC) that runs `kube-bench run --benchmark <b>
  --targets <t>`, printing findings to **stdout** — both the human-readable summary and (default) `--json`
  for a log pipeline (Loki/Alloy) to parse per-check results. No output file, no external sink to wire.
- A **read-only ServiceAccount + ClusterRole** (`get`/`list`/`watch` only, on the specific kinds the
  `policies` target inspects — RBAC, NetworkPolicies, namespaces/pods/SAs). No wildcards, no write verbs:
  the scan never mutates the cluster.

## Read-only by construction

- Host paths (`/var/lib/kubelet`, `/etc/systemd`, `/etc/kubernetes`) are mounted **`readOnly: true`**.
- Container runs as root (to read root-owned host config) but with **no privilege escalation**, **all
  capabilities dropped**, **`seccompProfile: RuntimeDefault`**, and a **read-only root filesystem** (an
  `emptyDir` backs `/tmp`). This is host-config *reading*, not a privileged container.
- RBAC is read-only; AWS/`managedservices` checks (which would need cloud creds) are omitted by default.

## Key inputs

- `image` (default `docker.io/aquasec/kube-bench:v0.15.6`) — validated to reject `:latest`/untagged.
- `benchmark` (default `eks-1.8.0`) — EKS can't self-detect the managed control plane, so it is passed
  explicitly; see kube-bench `cfg/` for supported `eks-*` versions.
- `targets` (default `node,policies`), `json_output` (default `true`), `schedule` (default `0 6 * * *`).
- `resources`, `node_selector`, `tolerations`, `namespace`, history/TTL limits, `tags`.

## Outputs

- `namespace`, `cronjob_name`.

## Notes / limitations

- A CronJob runs **one pod on one node**, so each run scans whichever node it lands on. Nodes in a managed
  group are homogeneous, so this is representative for the `node` CIS checks; broadening to every node
  (a DaemonSet-style sweep) is a follow-up if per-node drift needs tracking.
- Findings surface in the pod logs today. Alerting/dashboards on scan results (a Loki-derived metric or a
  parser) are a follow-up, mirroring how falco routing is layered on after the detections land.

## Dependencies (live unit)

`eks`, `node-groups` (the scan pod needs a node to land on and host paths to read). No AWS IAM in this
module.

## Related

- Issue #1149 — the CIS benchmark / node-hardening security gap (this is the scan half).
- ADR-045 (`falco`) — the sibling cluster-security tool this module mirrors.
