# ADR-098: Package Registry — AWS CodeArtifact (with ECR Pull-Through Cache for the Docker Mirror)

**Date:** 2026-07-08

**Status:** Accepted — built + live 2026-07-09 ([#1249](https://github.com/asanexample/platform/issues/1249))

## Context

The platform has a first-class **container-image** registry — centralized ECR in the platform account,
cross-account pull, per-Product repos, immutable tags, lifecycle rules, cosign-verified (ADR-028, ADR-050,
ADR-014). It has **no equivalent for language packages.** As soon as tenant apps grow past a single service
they need somewhere to publish and consume private **npm / PyPI / Maven / NuGet** packages, and — just as
importantly — a **proxy/cache of public upstreams** (npmjs, PyPI, Maven Central, …) so builds don't depend
on third-party registry availability, rate limits, or a supply-chain incident on the public internet. ECR
handles OCI artifacts (images, Helm charts, signatures, SBOMs); it does nothing for these package formats.

A related, narrower gap is a **pull-through cache for public Docker images** (`docker.io`, `ghcr.io`,
`quay.io`, `registry.k8s.io`) so cluster and CI pulls of base/tooling images are mirrored into our own
account rather than hitting Docker Hub rate limits on every pull.

Two forces frame the decision:

1. **This is a reference platform whose mission is to demonstrate scale and governance.** A capped or
   bolt-on registry undercuts that.
2. **The platform's identity model is IAM- and Keycloak-native.** Runtime AWS access is EKS Pod Identity
   (ADR-047/041); CI access is GitHub OIDC federation (ADR-036); human/UI SSO is Keycloak (ADR-053). Any
   registry that requires its own local user directory and hand-minted tokens sits *outside* this model.

### Alternatives considered

**1. Self-hosted Sonatype Nexus Repository Community Edition.** The obvious "universal, open-source,
self-hosted" candidate — one tool covering Docker + npm + PyPI + Maven + NuGet + more, with proxy/hosted/group
repos. **Rejected.** The 2025-rebranded Community Edition is materially limited in exactly the dimensions this
platform cares about:

- **Hard usage caps** — 40,000 total components *or* 100,000 requests/day; exceeding either **blocks new
  components** until the deployment drops back under. These caps were *halved* in 3.87.0 (from 100k/200k), so
  the trend is downward. A scale-demonstrating platform gated behind a shrinking free tier is the wrong bet.
- **No SSO / SAML** (Pro-only). This collides with our access-as-code model (ADR-053). `oauth2-proxy` can't
  rescue it the way it fronts the Rollouts UI, because package clients (`npm`, `pip`, `docker`) authenticate
  to the registry **API** with tokens/basic-auth, not a browser OIDC flow — so CE means local Nexus users +
  hand-minted tokens off to the side of Keycloak/IAM.
- **No HA / single node / no zero-downtime upgrades** (Pro-only) — a single-instance SPOF in the
  build-and-deploy critical path, against ADR-085. We have already been burned by fragile single-instance
  auth DBs (Backstage/Keycloak SSO wedges).
- **Cloud blob-store support appears Pro-gated** ("Full Support for Azure, GCP, and AWS" is Pro), which would
  likely force local/EBS storage rather than S3.

**2. Self-hosted Harbor.** CNCF-graduated, genuinely high quality. **Rejected as a fit, not on merit:** Harbor
is an **OCI** registry (images, Helm, OCI artifacts, proxy cache, Trivy, cosign). It does *not* serve
npm/PyPI/Maven/etc., so it would largely duplicate ECR (which is more integrated here) while leaving the
actual gap — language packages — unfilled.

**3. JFrog Artifactory OSS.** The OSS tier is far more limited than Nexus CE (effectively Maven/Gradle/Ivy +
generic; no Docker, npm, or PyPI without a paid tier). Not viable.

**4. GitHub Packages.** We already live on GitHub. **Rejected:** it's SaaS-tied, its auth is GitHub-token- /
PAT-based rather than IAM/Pod-Identity, and it pulls package hosting off the platform we're demonstrating. It
doesn't extend the ECR/Pod-Identity pattern we already operate.

**5. AWS CodeArtifact + ECR pull-through cache (chosen).** The managed AWS package registry is the packages
sibling to ECR: same account topology, same IAM/OIDC auth model, no caps, HA and S3-backed by AWS, KMS
encryption, and native **upstream external connections** that proxy+cache public repos. The Docker-mirror gap
is closed by ECR's own **pull-through cache** rules — no new tool. The single real gap is **Go modules**
(unsupported by CodeArtifact), handled as a caveat below.

## Decision

Adopt **AWS CodeArtifact** as the platform's package registry, and enable **ECR pull-through cache** for the
public-Docker mirror. Treat both as managed extensions of the existing ECR/Pod-Identity/OIDC pattern rather
than new self-hosted services.

**D1 — Centralized CodeArtifact domain in the platform account, cross-account read.** A single CodeArtifact
**domain** in the platform account (`<PLATFORM_ACCOUNT_ID>`) is the dedupe + encryption boundary (one KMS
key, one asset store). Repositories live within it. A **domain permissions policy** grants read to the
preprod and prod account principals, mirroring ECR's centralized-registry-with-cross-account-pull design
(ADR-028). CI publishes once; environments read the same package versions. Managed by a new
`infra/modules/aws/codeartifact/` module + a live unit alongside the `ecr` unit.

**D2 — Docker pull-through cache is ECR-native, not a new registry.** Create ECR **pull-through cache rules**
for `docker.io`, `ghcr.io`, `quay.io`, and `registry.k8s.io`. AWS supports **anonymous** pull-through for
`registry.k8s.io` and `quay.io` (and `public.ecr.aws`); `docker.io` and `ghcr.io` each **require** an upstream
credential in Secrets Manager (the secret name must start with `ecr-pullthroughcache/`) — so each of those is
enabled as its credential is provisioned, while the `registry.k8s.io` + `quay.io` mirrors work standalone. Public base/tooling images
are then lazily mirrored into our account on first pull and served with the same IAM auth as our own images.
This closes the "pull-through docker cache" need without adopting Harbor or a registry mirror.

**D3 — Auth reuses the existing model; no local users, no SSO problem.** Runtime consumers authenticate via
**EKS Pod Identity** (ADR-047/041) to call `codeartifact:GetAuthorizationToken` and read; **CI** publishes via
**GitHub OIDC** (ADR-036) assuming a scoped role. There is no CodeArtifact user directory and no Keycloak
integration to build — the SSO gap that sinks self-hosted CE simply does not exist, because access *is* IAM.

**D4 — Per-Team/Product scoping + upstream connections, derived from the Product registry.** Repositories are
scoped per Team/Product (matching ECR's `team-<team>/<product>-<svc>` intent), with **upstream external
connections** to the public sources each format needs (`public:npmjs`, `public:pypi`,
`public:maven-central`, `public:nuget-org`, …) so first requests cache through and later requests are served
locally. Repository/derivation config follows registries-as-single-source (ADR-069) rather than a hand-kept
map, consistent with how `ecr`/`policy`/`github-oidc` already derive per-Product.

**D5 — Go modules are a known gap, handled out-of-band.** CodeArtifact does **not** serve Go modules. Go
dependency caching is deferred to a follow-up — either an **Athens** GOPROXY (self-hosted, but a stateless
cache, not an identity-bearing registry) or accepting direct `GOPROXY` (which we already do for `crank`; see
the Crossplane-CLI-in-CI note). This ADR does not commit to Go module hosting.

## Consequences

### Positive

- **Fills the actual gap** (language packages) without duplicating ECR, and closes the Docker-mirror need with
  a native ECR feature — one coherent AWS-native registry story (images *and* packages) under one auth model.
- **No caps, HA, S3-backed, KMS-encrypted** by AWS — no single-instance SPOF in the build/deploy path, in
  keeping with ADR-085.
- **Zero new identity surface.** Pod Identity + GitHub OIDC already exist; there is no local user store, no
  SSO wiring, and no long-lived credentials — consistent with the `restrict-iam-users` SCP.
- **Supply-chain posture improves** — builds resolve public dependencies through cached upstreams we control,
  reducing exposure to public-registry outages, rate limits, and tampering; a natural home for future
  package-level scanning/provenance.
- **On-brand showcase.** The demonstration is the *governed, registry-derived, Pod-Identity-scoped* package
  access pattern — not operating a JVM monolith.

### Negative

- **AWS coupling.** Packages join images in being AWS-managed; there is no portable self-hosted artifact
  plane. Accepted — it is the same trade already made for ECR and consistent with the AWS-only posture.
- **Format coverage is finite.** CodeArtifact covers npm/PyPI/Maven/NuGet/generic and several others, but the
  exact matrix must be confirmed against teams' real languages before rollout — and **Go is not covered**
  (D5).
- **Client configuration is per-tool.** Each package manager needs endpoint + token wiring (the token is
  short-lived, ≤12h), so tenant CI and dev tooling need a small, documented bootstrap (a scaffolder concern).

### Risks

- **Token/permission sprawl.** Per-Product read/publish scoping via IAM must be derived correctly from the
  registry, or a product could read/publish outside its scope. Mitigated by deriving from the Product registry
  (ADR-069) and reviewing the domain/repository permission policies like we review ECR's.
- **Cost of cached upstreams.** Proxying large public ecosystems into CodeArtifact incurs storage + request
  cost; unbounded caching could surprise. Mitigated by scoping upstream connections to formats actually used
  and folding CodeArtifact into the FinOps guardrails (ADR-091/092).
- **New-account onboarding drift.** Like ECR's `pull_account_ids`, the domain permissions policy must be
  updated when a new account is added — add it to the new-account onboarding checklist.

## Implementation notes (as-built)

Built and applied across four units on 2026-07-09 (epic [#1249](https://github.com/asanexample/platform/issues/1249); PRs #1255 module + live unit + PTC, #1257 auth wiring, #1260 client bootstrap, #1261 the PTC fix below). All applied from the main checkout with `0 to destroy`. Verified live: domain `refplat` Active with 9 repositories (5 per-Product consumer + 4 store), `alpha-shop` upstreamed to all four store repos, the 5 per-Product OIDC roles carrying publish, and the **baseline read reconciled onto a live preprod Pod-Identity role** (`Pod-alpha-shop-dev-web` — a service with no declared permissions — now reads `refplat/alpha-shop` cross-account).

**Correction to D2 — ECR pull-through cache anonymous upstreams.** D2 originally implied all four upstreams could be created uniformly. In practice AWS accepts an **anonymous** pull-through rule only for `registry.k8s.io` and `quay.io` (and `public.ecr.aws`); `docker.io` and `ghcr.io` **require** a Secrets Manager credential (`ecr-pullthroughcache/<name>`) or `CreatePullThroughCacheRule` fails with `UnsupportedUpstreamRegistryException`. The first apply proved this: `k8s` + `quay` were created credential-free, `ghcr` failed. So the live rules are `k8s` + `quay`; `docker.io`/`ghcr.io` are wired but gated on their credentials (PR #1261). The D2 text above reflects the corrected behaviour.

**Refinements.** Runtime read is granted as a **baseline for every service** (not per-claim) via a new `codeArtifactDomain` EnvironmentConfig field on the Composition — empty renders byte-identically to pre-ADR-098, so clusters without CodeArtifact are unaffected. The platform-account domain owner is parsed from `ecrRegistry` (no new config plumbing).

**Follow-ups.** Populate the `docker-hub` / `ghcr` pull-through credentials to enable those two mirrors; the shared `trusted-ci` build workflows do not run `codeartifact login` by default (apps add it when they need private/cached packages); Go modules remain unserved (D5).

## Related

- [ADR-028: ECR Cross-Account Container Registry](028-ecr-cross-account-container-registry.md) — the OCI sibling; same centralized-with-cross-account-read topology.
- [ADR-036: GitHub Actions OIDC Federation for CI/CD](036-github-actions-oidc-federation.md) — CI publish auth.
- [ADR-047: EKS Pod Identity as the Standard for Pod AWS Identity](047-pod-identity-as-aws-identity-standard.md), [ADR-041: EKS Pod Identity for Tenant Workloads](041-pod-identity-for-tenant-workloads.md) — runtime read auth.
- [ADR-053: Identity & Cross-System Authorization Strategy](053-identity-and-cross-system-authorization-strategy.md) — why a local-user/SSO-gated registry is off-model.
- [ADR-069: Delivery Source-of-Truth — Product Registry + Environment Claims](069-delivery-source-of-truth-product-environment.md) — per-Product derivation.
- [ADR-050: Shared `build-sign` Reusable Workflow](050-shared-build-sign-reusable-workflow.md), [ADR-085: Workload Availability & Graceful-Disruption Defaults](085-workload-availability-graceful-disruption-defaults.md) — supply-chain and availability posture referenced above.
