# falco

Deploys **Falco** — runtime threat detection (ADR-045) — via the `falcosecurity/falco` Helm chart, plus the
bundled **falcosidekick** alert-routing layer. Falco runs as a privileged DaemonSet on every node, watching
syscalls/kernel events for suspicious runtime behaviour. It uses the **modern eBPF (CO-RE)** probe by default,
so there is no kernel-module/driver build — correct for the AL2023 6.x nodes, and it coexists with Cilium's eBPF
(different hooks).

## What it deploys

- A **Falco DaemonSet** in a dedicated `falco` namespace (kept out of tenant/PSA-restricted namespaces because
  it needs privileged eBPF access). Tolerates all taints (`operator: Exists`) so it runs cluster-wide.
- **JSON output** enabled (`json_output`, `json_include_output_property`) for clean downstream routing.
- **falcosidekick** (`enable_falcosidekick`, default `true`): the alert fan-out sidecar. With **no outputs
  configured it logs events to stdout** (verifiable today); SNS / Slack / observability destinations are layered
  on later via `falcosidekick_config` (#116) — e.g. `{ sns = { topicarn = "..." } }` once an SNS topic exists
  (see the `aws/sns-notifications` module).

## Key inputs

- `driver_kind` (default `modern_ebpf`; one of `modern_ebpf` / `ebpf` / `kmod`).
- `enable_falcosidekick` (default `true`), `falcosidekick_config` (extra output destinations, merged into the
  chart's `falcosidekick.config`).
- `helm_chart_version` (default `9.0.0`), `falco_resources`, `namespace`, `helm_wait`.

## Outputs

- `namespace` — where Falco is deployed.
- `helm_release_status`.

## Dependencies (live unit)

`eks`, `node-groups` (the DaemonSet needs nodes). No AWS IAM in this module — SNS publish is granted to the
falcosidekick identity on the topic side once routing is wired.

## Related ADRs

- ADR-045: Falco runtime threat detection
