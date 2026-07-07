# Documentation inventory — the full map

> Meta-doc, and a **living plan**. This is the *intended scope* of the portal — every course we mean to
> build over time, grounded in the real platform subsystems — so each new doc slots into a plan instead of
> accreting ad hoc. [The portal hub](README.md) lists what exists **today**; this lists where it's going.
>
> Each module is **Orientation + Reference** at minimum (plus a [glossary](glossary.md) link). Optional
> tiers — deep dive · tutorial · cheatsheet · troubleshooting — are added **only where a subsystem earns
> them** (see [the mold](_mold.md)); a typical module is two files, not seven.
>
> **This is aspirational.** It's the full map, not a committed backlog. **The spine is complete** and **five
> modules** are built (domain model, Environment API, Delivery, Policy, Identity & access) — the crosslink-debt
> trio is done; the near-term is now breadth on demand (a real reader, a demo, interest). Granularity is a
> guess; modules will split and merge as we build. **Audience** is decided *per module* at build time, not
> per domain — most are platform-engineer-facing; the genuinely developer-facing ones are called out in the
> notes.

**Status:** ✅ built · 🔜 next · ⏳ planned

## The spine — portal-level, cross-cutting

The docs that tie the per-module courses into a whole. Not subsystem modules — *system-level* orientation.

| Doc | What it covers | Status |
| --- | --- | --- |
| **[The Life of a Deployment](spine/life-of-a-deployment.md)** | one `git push` traced end-to-end across every plane — the narrative onramp (control plane) | ✅ |
| **[The Life of a Request](spine/life-of-a-request.md)** | one user request traced at runtime: edge → gateway → route → pod → signals (data plane) | ✅ |
| **[How the Platform Fits](spine/how-the-platform-fits.md)** | the control planes and how they hand off; the structural map (+ a "where this model comes from" canon) | ✅ |
| **[The Security Model](spine/the-security-model.md)** | defense-in-depth across the 4 C's, with an honest gaps register | ✅ |
| **[Why the Platform Exists](spine/why-the-platform-exists.md)** | the North Star / platform-engineering thesis (the "big why") | ✅ |
| Portal hub · Glossary | the index + shared vocabulary | ✅ |

## 1 · Foundations — a sub-curriculum

The substrate everything sits on — broad enough to be its own sub-curriculum. **✅ Built** as
[Foundations](foundations/): an orientation *tour of the whole substrate* + five deep dives (the account
model & SCPs · infrastructure-as-code · networking · the cluster & Cilium · nodes, scaling & access) covering
all six areas below. Two axes: the **AWS estate** (accounts · IaC · networking) and the **cluster** (CNI ·
nodes · ingress · access):

| Module | Covers | Status |
| --- | --- | --- |
| **Accounts & IaC** | multi-account AWS (orgs, OUs, SCPs), the IAM role model, OpenTofu + Terragrunt, remote state, SOPS secrets, CloudTrail (ADR-001/003/004/005/007/016/066) | ✅ |
| **Networking** | VPCs, Transit Gateway hub-spoke, CIDR strategy, cross-VPC DNS, private connectivity (ADR-015/034/035) | ✅ |
| **The cluster & CNI** | EKS (private API), component separation, Cilium CNI + kube-proxy replacement (ADR-008/009/010) | ✅ |
| **Nodes & compute** | managed node groups, Karpenter, the descheduler, elasticity (ADR-023/078/093) | ✅ |
| **Ingress & traffic** | Gateway API + HTTPRoute, cert-manager, external-dns, the NLB, hostname convention, TLS (ADR-017/022/029/030/060/061) | ✅ |
| **Cluster access** | the private-only endpoint, Tailscale, SSM bastion (ADR-010/011/020) | ✅ |

*Likely finer as built: **State bootstrap** (greenfield) and **DNS architecture** could stand alone —
module or deep dive, decided then.*

## 2 · The domain model & provisioning

| Module | Covers | Status |
| --- | --- | --- |
| **Domain model** | Team / Product / Service / Environment / Customer; the shared vocabulary | ✅ |
| **[Onboarding a Product](products/)** | the Product registry as single source of truth; three derivations (github-oidc/policy/argocd-apps); the paved road + onboarding how-to (ADR-069/067) | ✅ |
| **Environment API** | Crossplane: one claim → the full footprint (namespace, ECR, IAM, policies) | ✅ |
| **[Self-service cloud resources](self-service-resources/)** | S3 / SQS / SNS / DynamoDB via the claim; derived least-privilege IAM (ADR-073) | ✅ |

## 3 · Delivery

| Module | Covers | Status |
| --- | --- | --- |
| **[Delivery](delivery/)** | built as *one combined module* — ArgoCD GitOps + per-Product ApplicationSets, the health-gated promotion ladder, and progressive (canary) rollout | ✅ |
| **Progressive delivery** | Argo Rollouts, canary, weighted HTTPRoutes, metric-gated analysis (ADR-056) — *covered in the Delivery module; may split to its own deep dive* | ✅ |
| **Promotion & release** | promote-by-digest, `Release` records, the auto ≤ staging / gated-prod ladder (ADR-071) — *covered in the Delivery module* | ✅ |
| **Zero-downtime** | graceful drain, PDBs, topology spread, replica floor (ADR-085) — *a guide already exists* | ⏳ |

## 4 · Policy, supply chain & runtime security

| Module | Covers | Status |
| --- | --- | --- |
| **[Policy & admission](policy/)** | Kyverno — the guardrail engine (validate/mutate/generate); the per-cluster catalog; Audit→Enforce (ADR-014) | ✅ |
| **[Supply chain](supply-chain/)** | cosign keyless signing, SLSA provenance, the shared build-sign workflow + self-hosted CI runners, verify-at-admission (ADR-042/050/065) | ✅ |
| **Runtime security** | Falco runtime threat detection (ADR-045) | ⏳ |
| **Compliance & regulated workloads** *(placeholder — thin today)* | the *intent*: tiers as isolation/recovery floors, regulated-tier hardening, continuous control evidence, east-west zero-trust (ADR-013/055/057). **More aspiration than implementation right now — the module will say so honestly rather than overselling.** | ⏳ |

*Both **Policy** and **Supply chain** are **built** as single combined modules; each stays dense enough to
fracture later — Policy into engine/admission · the catalog · mutate/generate · audit→enforce; Supply chain
into signing · provenance (SLSA) · verify-at-admission · CI runners — a **deep dive** each, if a reader
needs it.*

## 5 · Identity & access — a sub-curriculum

Two axes: **who you are** (identity/SSO) and **what you may do** (access + governance). ✅ **A combined
[Identity & access](identity/) module is built** — it teaches all of the below at orientation depth
(decide-once-derive-everywhere + temporary power); deeper per-topic cuts may split later. The second axis
crams several distinct models:

| Module | Covers | Status |
| --- | --- | --- |
| **Identity & SSO** | Keycloak as the IdP of record, OIDC for ArgoCD/Backstage/Grafana, oauth2-proxy, the pluggable seam, admin-plane hardening (ADR-053/059/087) | ✅ |
| **Workload identity** | EKS Pod Identity — how a pod gets AWS credentials via its ServiceAccount, no static keys (ADR-041/047) | ✅ |
| **Human access & RBAC** | per-team kubectl RBAC, the platform-engineer access model, product-scoped / cross-team access (ADR-039/040/068) | ✅ |
| **The governance registry** | people / roles / grants as one git-native source, projected per-cluster; the layer glossary (ADR-089/090) | ✅ |
| **Temporary power** | just-in-time elevation, the activation operator, emergency revocation (ADR-088) | ✅ |
| **On-call & owner routing** | the identity directory, PagerDuty on-call, owner resolution (ADR-084) | ⏳ |

## 6 · Secrets & config

| Module | Covers | Status |
| --- | --- | --- |
| **Secrets & config** | External Secrets Operator, Secrets Manager, SOPS config-in-git, the app config/secrets paved road (ADR-019/066/070) | ⏳ |

## 7 · Observability — a sub-curriculum

Not one domain so much as a **sub-curriculum** — the broadest surface (~17 sub-modules), and the one that
keeps decomposing. It splits along two axes: by **signal** (metrics · logs · traces · profiles) and by
**lifecycle** (collect → store → query → instrument → alert → explore), plus multi-tenancy and agent-obs on
their own. The list below is the **first cut** — top-level models — and it's *expected* to go finer as it's
built: continuous profiling (eBPF/Pyroscope), the collection pipeline (Alloy/OTel), and dashboards &
correlation are each deep enough to become their own **module or deep dive**. We don't pin the leaves now.

Keep two of these sharply distinct or they'll bleed: **the stack** is *our architecture* (how we run the
backends); **the four signals** is vendor-neutral *signal literacy* (when to reach for a trace vs. a log).

| Module | Covers | Status |
| --- | --- | --- |
| **The observability stack** | LGTM+P storage + Grafana, hub-and-spoke topology, the collect→store→query data flow (ADR-043/044) | ⏳ |
| **Multi-tenancy & isolation** | per-team signal isolation — cortex-tenant, tenant-proxy (the P13 work) | ⏳ |
| **The four signals** | metrics · logs · traces · profiles — what each is, when to reach for it, how they correlate | ⏳ |
| **Instrumenting a workload** | auto-instrumentation (Beyla / eBPF) + OpenTelemetry (operator/collector), RED metrics, free vs. add | ⏳ |
| **SLOs, alerting & synthetics** | Sloth SLOs, burn-rate alerts, routing → on-call, black-box + k6 synthetics (ADR-077) | ⏳ |
| **Agent / GenAI observability** | OTel + GenAI semconv, per-invocation agent traces (ADR-076) | ⏳ |

*Likely finer splits as it's built: **Continuous profiling** (eBPF/Pyroscope) · **The collection
pipeline** (Alloy / OTel collector / prometheus-agent) · **Dashboards & correlation** (Grafana, exemplars,
trace↔logs) — module or deep dive, decided then.*

## 8 · Cost & FinOps

| Module | Covers | Status |
| --- | --- | --- |
| **Cost & FinOps** | CUR→Athena true-spend, per-team budgets/guardrails, OpenCost, the FinOps operating model (ADR-091/092) | ⏳ |

## 9 · The agentic platform — a sub-curriculum

A novel, headline area — really its own small curriculum: the runtime, the governance model, building one,
evaluating one.

| Module | Covers | Status |
| --- | --- | --- |
| **The XAgent runtime** | the GitOps-native agent control plane — the claim, the envelope, the kill-switch (ADR-082) | ⏳ |
| **Graduated autonomy & guardrails** | the autonomy ladder — per-action-class autonomy under machine-enforced guardrails (ADR-086) | ⏳ |
| **Building & operating an agent** | the envelope in practice, with the triage copilot as the worked example (ADR-080/081) | ⏳ |
| **Agent evaluation** | eval-as-a-service, the eval store — the gate the autonomy ladder waits on | ⏳ |

*(Agent / GenAI observability lives in the [Observability](#7--observability--a-sub-curriculum)
sub-curriculum, not here.)*

## 10 · Developer experience

| Module | Covers | Status |
| --- | --- | --- |
| **The paved road** | New Product scaffolding, the golden-path starters, "ship a service" end-to-end | ⏳ |
| **Backstage portal** | the developer portal, catalog projection, plugins, auth (ADR-051/064) | ⏳ |

## 11 · Operations & lifecycle

| Module | Covers | Status |
| --- | --- | --- |
| **platctl & lifecycle** | the orchestrator (bootstrap / teardown / validate), cluster parking, rebuild-from-scratch, resilience/BC, the platform's own stateful components (CloudNativePG) (ADR-038/054) | ⏳ |

## Build sequence

The tension: the **spine** and the **modules** are mutually dependent — "Life of a Deployment" *traverses*
delivery/policy/identity, so it can't be written *well* before them; but the modules cohere better once the
map exists. The resolution: build the spine as a **skeleton first** (the map + the flow, linking to arch
docs for gaps), then thicken it as modules land.

Rough order, and it's **debt-driven** — build what the *existing* docs already reference
(see [`_crosslinks.md`](_crosslinks.md)):

1. **Spine — ✅ DONE (all 5 docs).** Why-it-exists · Life-of-a-Deployment · Life-of-a-Request · How-it-Fits ·
   the Security Model. These cohere the two built modules (domain model, Environment API) — *and* create the
   crosslink debt the next modules pay down (every spine doc forward-refs "coming: Delivery / Policy /
   Identity / Observability…").
2. **The crosslink-debt modules — ✅ DONE.** **Delivery**, **Policy & admission**, and **Identity & access**
   are built — the provisioning → delivery → policy → identity loop the spine forward-referenced is closed.
   (**Foundations** is now built too — the whole substrate (orientation + 5 deep dives).)
3. **← WE ARE HERE: breadth on demand** — Observability, Cost, the Agentic platform, Developer
   experience, Operations. (The quick adjacent win **Self-service cloud resources** — extending the
   Environment API module — is now built.) Pulled in as a real reader, a demo, or interest calls for them; no obligation to
   build all 24.

## Notes

- **Developer-facing modules** (the rest are platform-engineer-facing): the **domain model**, **self-service
  resources**, **the paved road**, **cost**, and the developer halves of **delivery** / **zero-downtime** /
  **observability**. Audience is finalized per-module at build (per the mold's expertise-reversal split).
- **Mechanism modules** (Environment API, delivery, policy, observability, the cluster, foundations,
  agentic) are the ones likely to *earn* deep dives and cheatsheets.
- **How-to stays in the runbooks** — the portal teaches and references; the runbooks own the operational
  task recipes. Link, don't duplicate.
- **Reader paths** (new-engineer path · developer path) are the hub's job, not this doc's — keep them in
  step in [`README.md`](README.md) as modules ship.
- Keep this inventory and the hub's module table in step as things land.
