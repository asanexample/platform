# Learn the Platform

A **teaching** layer for the platform. The ADRs record *why* we decided things; the runbooks tell you
*how* to do a task; the architecture docs are *reference*. This is the missing fourth thing — docs whose
job is to **build the mental model** in someone who doesn't have it yet, from the ground up.

Each subsystem is a short course: an **Orientation** (a guided journey you read start to finish) and a
**Reference** (look-up once you have the model) — plus, for the deeper subsystems, optional **deep dives**
(open one hard mechanism) and **tutorials** (hands-on, learn-by-doing).

## Start here

| You are… | Start with |
| --- | --- |
| **You want the point before the parts** | [Why the Platform Exists](spine/why-the-platform-exists.md) — the problem it solves and the one-sentence thesis, before any machinery. |
| **New to the platform** | The [domain model](domain-model/orientation.md) — the shared vocabulary (Team / Product / Service / Environment) everything else is built on. Read it first. |
| **Curious how it all fits together** | [The Life of a Deployment](spine/life-of-a-deployment.md) — one `git push` traced across every control plane. The big-picture map the modules hang off. |
| **Ready for how things are built** | The [Environment API](environment-api/orientation.md) — the clearest example of how the platform turns a declaration into running infrastructure. |
| **A developer shipping a service** | The [domain model](domain-model/orientation.md) (it's the model your code lives in), then the "developer's 2-minute view" at the end of each orientation. |
| **Extending or operating a subsystem** | That subsystem's Reference, then its house skill / runbook (linked at the bottom of each module). |

## Modules

| Module | Status |
| --- | --- |
| **[Domain model](domain-model/)** — Team / Product / Service / Environment: the shared vocabulary (**start here**) | ✅ available |
| **[Environment API](environment-api/)** — how environments get provisioned (Crossplane) | ✅ available |
| **[Delivery](delivery/)** — git → running across stages, safely (ArgoCD, the promotion ladder, Rollouts) | ✅ available |
| Observability — the LGTM+P stack | ⏳ planned |
| **[Policy & admission](policy/)** — the guardrail engine at the cluster door (Kyverno: validate · mutate · generate) | ✅ available |
| **[Identity & access](identity/)** — decide once, derive everywhere, borrow dangerous power (Keycloak, Pod Identity, temporary power) | ✅ available |
| Supply chain — signing, provenance, verification | ⏳ planned |
| The agentic platform — running governed AI agents | ⏳ planned |
| Cost & FinOps | ⏳ planned |
| **[*Spine:* The Life of a Deployment](spine/life-of-a-deployment.md)** — one `git push` across every plane (control plane) | ✅ available |
| **[*Spine:* The Life of a Request](spine/life-of-a-request.md)** — one user request, edge to pod (data plane) | ✅ available |
| **[*Spine:* How the Platform Fits](spine/how-the-platform-fits.md)** — the control-plane map (the same structure at rest) | ✅ available |
| **[*Spine:* The Security Model](spine/the-security-model.md)** — the same layers as concentric defenses (defense in depth) | ✅ available |
| **[*Spine:* Why the Platform Exists](spine/why-the-platform-exists.md)** — the North Star behind all the machinery | ✅ available |

> The portal is being built **one subsystem at a time**, proving the format before scaling. The domain
> model (the foundation) and the Environment API (the first worked subsystem) exist today; the planned
> modules are listed so the shape of the whole is visible, not because they exist yet.

## Reference aids

- **[Glossary](glossary.md)** — the shared vocabulary that recurs across modules (namespace, Composition,
  admission, Team / Product / …), each with a link to its canonical doc. Look a term up here; the modules
  teach it in context.

## For authors

The **[inventory](_inventory.md)** is the master plan — every course the portal intends to cover, by
domain, with a build sequence. New modules are written against **[the mold](_mold.md)** — the shared
template + rules that keep the portal one consistent voice. Read both before adding a module. Finishing a
module includes the **crosslink pass** and clearing any rows you satisfy in the
**[crosslink backlog](_crosslinks.md)**.
