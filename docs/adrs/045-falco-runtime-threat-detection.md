# ADR-045: Falco for Runtime Threat Detection

**Date:** 2026-05-31

**Status:** Accepted — deployed on the **preprod** cluster (modern eBPF), platform #116 / PR #134.
Complements admission-time policy ([ADR-014](014-kyverno-as-policy-engine.md)) and supply-chain verification
([ADR-042](042-isolated-build-provenance-slsa-l3.md)) with the runtime layer of defense in depth.

## Context

The platform gates **what gets deployed**: Kyverno enforces pod hardening + multi-tenancy at admission
([ADR-014](014-kyverno-as-policy-engine.md)), and the supply chain verifies image signatures + SBOM +
provenance ([ADR-042](042-isolated-build-provenance-slsa-l3.md)). Nothing watches workloads **at runtime**.
Once a (signed, compliant) container is running, an exploit, a malicious dependency, or a compromised process
can do things admission can't see: spawn a shell in a container, read sensitive files, escalate privileges,
make unexpected outbound connections, or write to system binaries. Defense in depth needs a **runtime
detection** layer.

### Alternatives considered

**1. Falco (chosen).** CNCF-**graduated** runtime security; a per-node DaemonSet that taps syscalls and emits
events against a maintained rules-as-code ruleset, with `falcosidekick` for alert routing. **Modern eBPF
(CO-RE)** probe — no kernel-module/driver build, works on the AL2023 6.x nodes, and coexists with Cilium's
eBPF (different hooks). OSS, portable, mature out-of-the-box rules.

**2. Cilium Tetragon (rejected/close).** eBPF-based, from the same project as our CNI (Cilium) — strong
synergy and in-kernel enforcement potential. But Tetragon is more a low-level observability/enforcement
*primitive* that needs significant policy authoring to reach parity, whereas Falco ships a mature,
CNCF-curated detection ruleset and the falcosidekick routing ecosystem out of the box. A reasonable future
reconsideration given we already run Cilium — revisit if we want in-kernel *enforcement* (not just detection).

**3. AWS GuardDuty Runtime Monitoring for EKS (rejected).** Managed, agent-based, low-effort. But: per-vCPU
pricing, an opaque/non-tunable rule set, AWS-only (not portable for the OSS-default platform), and a managed
black box vs. rules-as-code. Could complement Falco at the account level; not a substitute for tunable
in-cluster detection.

**4. Tracee (Aqua) (rejected).** Similar eBPF approach; less adoption / smaller ecosystem than Falco.

**5. Nothing — rely on admission + supply chain (rejected).** Leaves the entire runtime blind; admission is
a point-in-time gate, not continuous monitoring.

## Decision

Run **Falco with the modern-eBPF (CO-RE) driver** as a per-node DaemonSet, in its own privileged namespace
(kept out of the tenant/PSA-restricted namespaces), deployed first on **preprod** — where tenant workloads
run and the runtime-attack surface is highest. JSON-structured output is on so downstream routing gets clean
fields, and **falcosidekick** is deployed as the alert-routing layer.

Rollout is deliberately staged:

- **Now (preprod):** Falco + falcosidekick deployed; detections go to **stdout** (verifiable immediately,
  zero alert-routing dependency).
- **Next:** route falcosidekick → **SNS** (the shared `platform-alerts` topic — the `sns-notifications`
  module already names Falco as a publisher) and into the **observability** stack ([ADR-043](043-self-hosted-observability-stack.md) /
  #102), so detections become real alerts + dashboards.
- **Later:** extend to the **platform** cluster; tune the ruleset to the platform's expected behavior to
  control false positives.

`driver_kind` is a variable (`modern_ebpf` / `ebpf` / `kmod`) defaulting to modern eBPF for the current
kernels.

## Consequences

### Positive

- **Completes defense in depth** — admission (Kyverno) + supply chain (cosign/SLSA) + **runtime (Falco)**;
  the running workload is no longer unobserved.
- **OSS, portable, low-overhead** — CNCF-graduated, modern eBPF (no kernel module fragility), rules-as-code,
  no per-vCPU licensing; coexists with Cilium's eBPF.
- **Integrates with the existing alerting path** — falcosidekick → the shared SNS topic + observability,
  reusing infrastructure we already run rather than a separate pipeline.
- **Tunable** — rules are code we control, unlike a managed black box.

### Negative

- **Preprod only today** — the **platform** cluster is not yet covered; runtime detection there is a gap
  until the rollout extends.
- **Detection, not prevention (by default)** — Falco alerts; it does not block. Response/automation is a
  later concern.
- **Alert routing not yet wired** — detections currently go to stdout; until falcosidekick → SNS/observability
  lands, nobody is paged. Tracking with #116/#102.
- **Tuning burden / false positives** — out-of-the-box rules flag legitimate platform behavior; an untuned
  ruleset risks alert fatigue once routing is on.
- **Per-node DaemonSet overhead + eBPF kernel sensitivity** — privileged pods on every node; modern eBPF
  needs kernel ≥ 5.8 (fine on AL2023 6.x, a constraint to remember for other node images).
