# Crosslink backlog

Meta-doc for authors, not a lesson. Heavy crosslinking is a hallmark of great documentation — but a
module can only link to targets that **exist**. Since the portal is built one subsystem at a time, most
crosslinks can't be written when a module is first authored; they have to be added *later*, once the
target module exists. This file tracks that debt so it doesn't get silently forgotten (the usual fate of
"we'll link it up eventually").

**The process (see [`_mold.md`](_mold.md)):** when you add a module, run the **bidirectional crosslink
pass** — grep every existing `docs/learn/**` for mentions of your subsystem, turn them into links to your
new module, link *out* from your module to any subsystem that already has one, and clear the matching
rows below.

## Pending — add these links once the target module exists

Each row is a forward-reference already sitting in a written module, waiting for its target to be built.

| Mentioned in | Term / concept | Target module (not yet written) |
| --- | --- | --- |
| `environment-api` (orientation §2, reference) | ArgoCD / GitOps delivery | delivery-pipeline (or argocd) |
| `environment-api` (orientation §3, reference) | Kyverno / admission policy | policy-and-admission |
| `domain-model` (orientation, "The Team is an envelope") | admission / policy engine / Kyverno / "policy regime" | policy-and-admission |
| `domain-model` (orientation, "One more deployment shape: agents") | agents / XAgent / autonomy / triage copilot | agentic-platform |
| `environment-api` (orientation "two AWS accounts"; reference "workload / platform account") | the multi-account model / cross-account (AWS Organizations) | cloud-foundations |
| `environment-api` (orientation §3, reference) | Pod Identity | identity-and-access |
| `environment-api` (reference) | cosign / verify-images / supply chain | supply-chain |
| `environment-api` (orientation, "Why not just do it by hand?") | the platform-wide purpose / platform-engineering thesis | portal-level "why this platform exists" (spine) |

Until a learn module exists for one of these, the mention may link to its **architecture doc or ADR**
where that genuinely helps the reader — just never to a learn page that doesn't exist yet.
