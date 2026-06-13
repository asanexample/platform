# Platform Glossary

Platform-specific terms, one or two lines each, with a link to the deep doc or ADR that defines them.
General Kubernetes/AWS terms are omitted. Alphabetical.

> **Last reviewed:** 2026-06-08

---

**App** — A deployable unit owned by a Team, declared as a key under `spec.apps.<app>` in the `XTenant`
claim. Each app gets an ECR repo `team-<team>/<app>`, a derived hostname, and (optionally) PR previews.
See [Multi-App Environment Model (ADR-031)](adrs/031-multi-app-environment-model.md).

**ApplicationSet (PR preview generator)** — An ArgoCD `ApplicationSet` (one per preview-enabled app) whose
`pullRequest`/GitHub generator polls the app repo every 60s and creates an ephemeral `Application` per open
PR. See [PR Preview Environments (ADR-032)](adrs/032-pr-preview-environments.md).

**BACK stack** — **B**ackstage + **A**rgoCD + **C**rossplane + **K**ubernetes: the chosen architecture for
developer self-service. ArgoCD delivers, Crossplane provisions environments, Backstage is the portal.
See [Adopt the BACK Stack (ADR-046)](adrs/046-back-stack-for-developer-self-service.md).

**Compliance tier** — `standard` / `hipaa` / `pci` posture on an environment (`spec.complianceTier`, default
`standard`). Regulated tiers add isolation, encryption, network, and retention requirements; on `standard`
clusters only `standard` is in use. See [Compliance Tier Model (ADR-013)](adrs/013-compliance-tier-model.md).

**Composition (Crossplane)** — The `Pipeline`-mode Composition that reconciles one `XTenant` into the full
environment footprint (namespace + AWS + cross-account ECR). Lives at `charts/environment-api/files/composition.yaml`.
See [Crossplane Environment API](architecture/crossplane-environment-api.md#what-the-composition-provisions).

**cosign / keyless signing** — Images must be cosign-signed (keyless, via Fulcio/Rekor) to pass admission.
Kyverno's `verify-images-team-<team>` admits the shared signer identity gated to the team's repo.
See [Cosign Image Signing](architecture/cosign-image-signing.md).

**Domain tiers (1/2/3)** — Tier 1 = the generated canonical host; tier 2 = a platform-domain vanity alias
(under `*.<baseDomain>`, free today); tier 3 = an external custom domain (e.g. `shop.acme.com`, deferred).
See [Environment Ingress & Custom Domain Strategy (ADR-061)](adrs/061-environment-ingress-and-custom-domain-strategy.md).

**ECR team-scoping** — Container images live in the platform account at `team-<team>/<app>`; Kyverno denies
cross-team image references and the preprod/prod accounts pull cross-account via a RepositoryPolicy.
See [ECR Cross-Account Registry (ADR-028)](adrs/028-ecr-cross-account-container-registry.md).

**EnvironmentConfig (`platform-cluster-config`)** — A Helm-templated Crossplane `EnvironmentConfig` carrying
per-cluster constants (ECR registry, account IDs, cluster name, `baseDomain`, boundary ARN) into the
Composition, so they never leak into the claim. See [Crossplane Environment API](architecture/crossplane-environment-api.md#composition-pipeline).

**federation (upstream IdP)** — Brokering authentication from an upstream identity provider (Okta / Entra /
Google / AWS IdC) into Keycloak via a one-block `upstream` swap; nothing downstream of Keycloak moves.
See [Pluggable IdP Seam (ADR-059)](adrs/059-identity-topology-pluggable-idp-seam.md).

**function-go-templating** — The Crossplane composition function that renders all environment resources (and, in
ADR-061 Phase 2a, the `status.domains` state machine) from `spec` + context, with no separate controller.
See [Crossplane Environment API](architecture/crossplane-environment-api.md#composition-pipeline).

**Generated host** — The system-canonical hostname `<app>-<team>.<env-domain>` derived from `(app, team,
env)` and injected into the app's HTTPRoute by argocd-apps — never hardcoded in the app repo. Previews use
`<app>-<team>-pr-<n>`. See [Environment App Hostname Convention (ADR-060)](adrs/060-environment-app-hostname-convention.md).

**IdP of record** — In the realized default (scenario B), Keycloak owns users and memberships in the
`platform` realm (`upstream = null`); upstream federation is opt-in.
See [Pluggable IdP Seam (ADR-059)](adrs/059-identity-topology-pluggable-idp-seam.md).

**IRSA (IAM Roles for Service Accounts)** — OIDC-federated pod AWS credentials via an
`eks.amazonaws.com/role-arn` SA annotation. Platform add-ons (cert-manager, external-dns, …) use it; environment
workloads must NOT (the annotation is denied for environments). See [Pod Identity Standard (ADR-047)](adrs/047-pod-identity-as-aws-identity-standard.md).

**Kyverno** — The admission policy engine (ADR-014), in Enforce mode on preprod and platform. Per-team
`restrict-images`/`restrict-route-hostnames` (claim-owned) + platform `verify-images`/`verify-attestations`.
See [Kyverno as Policy Engine (ADR-014)](adrs/014-kyverno-as-policy-engine.md) and the
[policy catalog](architecture/kyverno-policy-catalog.md).

**membership (binding)** — The person → team mapping a `groups` OIDC claim carries; bound from the upstream
group claim (default), the `_teams.hcl` registry (AWS IdC fallback), or the Keycloak admin UI.
See [Pluggable IdP Seam (ADR-059)](adrs/059-identity-topology-pluggable-idp-seam.md).

**platctl** — The DAG-aware Go CLI (`./bin/platctl`, built via `make build-platctl`, not on PATH) for
bootstrap, teardown, validate, and kubeconfig. See [platctl CLI (ADR-038)](adrs/038-platctl-cli-for-platform-operations.md).

**Pod Identity** — The go-forward standard for environment pod AWS access: an EKS Pod Identity association binds
a named ServiceAccount in `team-<team>` to `Pod-team-<team>` (capped by a deny-escalation boundary). No
OIDC trust boilerplate; works with `automountServiceAccountToken: false`.
See [Pod Identity Standard (ADR-047)](adrs/047-pod-identity-as-aws-identity-standard.md) and the
[Pod Identity runbook](runbooks/environment-aws-access-pod-identity.md).

**PR preview** — An ephemeral per-PR deployment (`<app>-<team>-pr-<n>.<env-domain>`) created for apps with
`preview = true`, via the ApplicationSet PR generator + kustomize overrides.
See [PR Preview Environments (ADR-032)](adrs/032-pr-preview-environments.md).

**restrict-route-hostnames** — The per-team Kyverno ClusterPolicy that admits an HTTPRoute hostname only if
it is in the team's allow-list (derived generated host ∪ `spec.domains`) **and** its `status.domains` entry
is `Active`. See [Crossplane Environment API](architecture/crossplane-environment-api.md#statusdomains--the-ingress-state-machine-adr-061-phase-2).

**seam (invariant)** — A stable contract whose providers are swappable: the identity seam (Keycloak +
`sso.aws.refplat.org`, ADR-059) and the ingress seam (`spec.domains`/`status.domains` + the shared Gateway,
ADR-061). See [Pluggable IdP Seam (ADR-059)](adrs/059-identity-topology-pluggable-idp-seam.md).

**shift-left** — Running the *same* Kyverno checks in the app repo's PR CI (the `kyverno-validate` composite
action) so non-compliant manifests fail before merge. A feedback gate, not a new enforcement gate.
See [Kyverno Shift-Left](architecture/kyverno-shift-left.md).

**SLSA provenance** — Build provenance attestation produced by the isolated, app-team-unwritable
`trusted-ci/slsa-provenance.yml`; Kyverno's `verify-attestations-team-<team>` enforces it (Enforce on
preprod). See [Isolated Build Provenance (ADR-042)](adrs/042-isolated-build-provenance-slsa-l3.md).

**`spec.domains`** — Structured environment intent for vanity/custom hosts (`[]` of `{ host, canonical?, dns? }`)
on the `XTenant` claim; the implicit generated host is never declared. The sole source of truth for
hostnames (replacing `teams.hcl`). See [ADR-061](adrs/061-environment-ingress-and-custom-domain-strategy.md).

**`status.domains`** — The ingress state machine the Composition writes (one entry per host with
`state`/`mode`/`reason`). A host is admitted only while `Active`; verification is the security boundary
(ADR-061 Phase 2a). See [Crossplane Environment API](architecture/crossplane-environment-api.md#statusdomains--the-ingress-state-machine-adr-061-phase-2).

**supply-chain split** — Per-team `restrict-*` guardrails live in the Environment Composition (claim-owned); the
platform-owned `verify-images`/`verify-attestations` trust roots stay in the `policy` module for all teams.
See [Cosign Image Signing](architecture/cosign-image-signing.md) and [ADR-046](adrs/046-back-stack-for-developer-self-service.md).

**Team** — The owner/identity dimension: an SSO group + a git-native `Team` CR (ADR-063). The v3 model (ADR-067)
separates ownership (Team) from the deployment unit (Environment = Product × Stage). A Team's envelope bounds
what Environments its members may provision. See [IDP Domain Model (ADR-067)](adrs/067-idp-domain-model.md).

**Tenant** *(deprecated, pre-ADR-067)* — The historical noun for the provisioned unit, now the **Environment**.
Older ADRs use the original term; current code/docs say Environment.

**Environment / XEnvironment** — A single declarative `XEnvironment` (cluster-scoped Crossplane XR,
`platform.refplat.org/v1alpha3`) that provisions one Environment — a Product at a Stage (namespace, quota,
network policy, Pod-Identity, GitOps delivery), bounded by the owning Team's envelope. The sole provisioning
path. See [Crossplane Environment API](architecture/crossplane-environment-api.md).

**trusted-ci / build-sign** — The shared, app-team-unwritable reusable workflow
(`asanexample/trusted-ci/build-sign.yml`) that builds → pushes → signs → SBOMs an image. App CI is a thin
caller of it. See [Shared build-sign Workflow (ADR-050)](adrs/050-shared-build-sign-reusable-workflow.md).

**`validation_failure_action`** — The Kyverno policy mode toggle: `Audit` (report-only) vs `Enforce`
(reject at admission). Preprod and platform run Enforce for environment policies.
See [Kyverno as Policy Engine (ADR-014)](adrs/014-kyverno-as-policy-engine.md).

**XRD** — The `CompositeResourceDefinition` (`xtenants.platform.refplat.org`) defining the `XTenant` schema
and its defaults (`resourceQuota`, `complianceTier`, …). See [Crossplane Environment API](architecture/crossplane-environment-api.md#the-environment-claim-xtenant).

**Zone** — A platform-owned isolation/placement unit (account + cluster keyed by environment, location,
hardening, tenancy) in the v2 environment model; not yet implemented (lands with the rebuild).
See [Environment Model — Team/Environment/Zone (ADR-049)](adrs/049-tenant-model-team-tenant-zone.md).
