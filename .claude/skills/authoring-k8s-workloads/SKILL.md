---
name: authoring-k8s-workloads
description: >-
  How to write Kubernetes manifests that pass Kyverno admission in this platform's
  ENVIRONMENT namespaces (preprod + platform run Kyverno in Enforce mode, so
  non-compliant resources are rejected at apply). Use whenever authoring or editing
  manifests destined for an environment namespace — an app repo's k8s/ overlays, a
  Deployment/StatefulSet/Service/HTTPRoute/ServiceAccount/Role bound for a
  <team>-<product>-<stage> namespace, or anything you're about to kubectl apply or
  hand to ArgoCD there. Consult it BEFORE writing the manifest so it isn't rejected
  for a missing probe, an unscoped image, a LoadBalancer Service, or an unsigned
  image. NOT for platform/system infra manifests (kube-system, argocd, kyverno,
  cert-manager, etc. are excluded from these policies), Terragrunt/OpenTofu, or the
  policy module itself.
---

# Authoring Kyverno-Compliant Kubernetes Workloads

Kyverno runs in **Enforce** mode on **both preprod and platform** (ADR-014). In an
environment namespace, a manifest that violates a policy is **rejected at admission** —
`kubectl apply` fails and ArgoCD shows the resource as failing to sync. This skill is the
author's-eye view of what's enforced so you write it right the first time. The
authoritative, generated catalog is `docs/architecture/kyverno-policy-catalog.md`; the
real policies live in `infra/modules/policy/policies-chart/templates/`.

## Where this applies — and where it doesn't

Policies target **environment namespaces**: those labeled `platform.refplat.org/team`
and named **`<team>-<product>-<stage>`** (e.g. `alpha-demo-dev`). The namespace name
**must end in a stage suffix** — `-dev`, `-test`, `-uat`, `-staging`, or `-prod` —
or the Namespace itself is rejected (`require-environment-namespace-naming`).

These do **not** apply to system/infra namespaces, which are excluded: `kube-system`,
`kube-node-lease`, `kube-public`, `kyverno`, `cert-manager`, `external-secrets`,
`external-dns`, `argocd`, `tailscale`. So platform component manifests aren't governed by
this skill — environment workloads are. Workloads in `default` are denied outright
(`disallow-default-namespace`).

## Auto-injected by `mutate` — do NOT set these

Kyverno adds these when absent, so leave them out (setting them is harmless but noise):

- **Container & initContainer `securityContext`** — `allowPrivilegeEscalation: false`,
  `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`
- **Pod `automountServiceAccountToken: false`**
- **The `team` label** on the Pod — auto-injected, derived from the namespace name (known derivation bug, tracked — the mutate rule currently picks the wrong token, so don't rely on its exact value)
- **Graceful-drain defaults** (ADR-085) — a container `lifecycle.preStop` (native `sleep`) +
  pod `terminationGracePeriodSeconds: 30`, so a rolling update / node disruption doesn't drop
  in-flight traffic. (`mutate-pod-defaults`.)
- **`topologySpreadConstraints`** (ADR-085) — across zone + node, soft (`ScheduleAnyway`), with a
  `labelSelector` derived from your workload's own selector, so replicas don't all land on one
  node/AZ. (`mutate-topology-spread`, matches the Deployment/StatefulSet directly.)

Note: **`app.kubernetes.io/name` is NOT auto-injected and NOT required** — it's
recommended (it can't be derived under autogen). Set it yourself if you want it.

## Auto-generated FOR you — do NOT author these

- **A `PodDisruptionBudget`** (`<workload>-pdb`, `maxUnavailable: 1`) is generated for every
  environment `Deployment`/`StatefulSet`, with a selector copied from your workload (ADR-085).
  Don't write your own — it's created, kept in sync, and garbage-collected when you delete the
  workload. It's drain-safe (`maxUnavailable: 1` never blocks a node drain) and only gives real
  protection once you run **≥ 2 replicas**.

## Availability is your job too (not enforced, but expected)

The platform makes deploys/disruptions *non-dropping*, but only if your app cooperates (ADR-085):

- **Run ≥ 2 replicas** for anything that should survive a rollout or node disruption — a single
  replica can't be zero-downtime, and its PDB/spread do nothing. In **`*-prod`** namespaces this is
  **required** (`require-prod-replica-floor`: `spec.replicas >= 2`) — **Enforce on both preprod and
  platform** (#934), so a single-replica `*-prod` workload is rejected at admission; an HPA must set
  `minReplicas >= 2`. (The module DEFAULT stays Audit for fresh clusters; the live clusters flipped to
  Enforce.) Lower stages may stay at 1 for cost. (Don't expect to mutate replicas — it's validated,
  never injected, so it doesn't fight your HPA/overlay.)
  - **You get a default HPA for free** (ADR-078 Phase 2, "elastic by construction"): the New Product
    scaffolder emits `k8s/base/hpa.yaml` — an `autoscaling/v2` HPA targeting the Rollout (CPU 70%,
    `minReplicas: 1` / `maxReplicas: 10`; the **prod overlay patches `minReplicas → 2`**, which is what
    satisfies the floor above). So a scaffolded prod service is compliant *and* elastic without authoring
    an HPA. Opt out by deleting the file + dropping it from `kustomization.yaml`. (The per-Product
    ApplicationSet ignores the Rollout `.spec.replicas` so the HPA owns scaling and ArgoCD doesn't fight it.)
- **Handle `SIGTERM`**: stop accepting new work, drain in-flight, exit. The injected `preStop` sleep
  only buys the window for the datapath to stop routing to you — it does **not** drain your
  in-flight requests; your process must. **Long-lived connections** (websockets, gRPC streams) need
  app-level connection-age limits / `GOAWAY` — the preStop sleep won't cover them.

## Required — or the resource is REJECTED

Every one of these is `Enforce` on preprod + platform. Omitting or violating it fails admission.

| Requirement | Policy | The rule |
|---|---|---|
| **Image from the team/product-scoped ECR** | `restrict-image-registries` | `<platform-acct>.dkr.ecr.us-east-1.amazonaws.com/team-<team>/<product>-<svc>` — cross-team/registry images denied |
| **Explicit immutable tag/digest** | `disallow-latest-tag` | must be tagged; never `:latest`, never untagged. Prefer a `@sha256:` digest |
| **CPU + memory `requests` AND `limits`** | `require-requests-limits` | both, on every container |
| **`livenessProbe` AND `readinessProbe`** | `require-pod-probes` | both, on every container |
| **Services are `ClusterIP`** | `block-public-loadbalancer` | `LoadBalancer` / `NodePort` denied — ingress is via the shared Gateway (`HTTPRoute`) |
| **Route hostnames in the allow-list** | `restrict-route-hostnames-<team>-<product>-<stage>` | HTTPRoute/GRPCRoute/TLSRoute hostnames must be in the Environment claim's `spec.domains`; another team's/platform's hostname, or an empty list, is denied (ADR-029) |
| **No IRSA annotation on ServiceAccounts** | `disallow-irsa-annotation-cross-team` | a ServiceAccount must NOT carry `eks.amazonaws.com/role-arn` — IRSA is platform-only; the annotation is a cross-team escalation and is denied |
| **No workloads in `default`** | `disallow-default-namespace` | use the `<team>-<product>-<stage>` namespace |
| **No privilege escalation / Unconfined seccomp** | `disallow-privilege-escalation`, `require-seccomp` | don't set `allowPrivilegeEscalation: true` or `seccompProfile.type: Unconfined` (backstops the mutate defaults) |
| **No `cluster-admin`, no wildcards in RBAC** | `restrict-binding-clusteradmin`, `restrict-wildcard-rbac` | (Cluster)RoleBindings to `cluster-admin` denied; Roles/ClusterRoles with `*` in `verbs`, `resources`, or `apiGroups` denied |
| **Images are cosign-signed (+ attested)** | `verify-images-product-*`, `verify-attestations-product-*` | image signature **and** SBOM + SLSA provenance are verified; **Enforce on both preprod and platform**. See "Image & supply chain" |

**Also use a named ServiceAccount** (`serviceAccountName`, never `default`) — but note this is a
**Pod Identity requirement, not a Kyverno rejection**: a `default` SA passes admission, it just
won't receive the platform-managed AWS credentials (the association binds creds to a named SA,
ADR-041). Declare the access in the `XEnvironment` claim, not on the SA.

## Image & supply chain

- **ECR path:** `829808296602.dkr.ecr.us-east-1.amazonaws.com/team-<team>/<product>-<svc>:<tag-or-digest>`
  (`829808296602` = platform account, `us-east-1`). The `team`/`product` derive from your
  `<team>-<product>` repo name, so cross-product pushes are structurally impossible.
- **Signing is not your job to implement.** Your app CI is a *thin caller* of the shared,
  app-team-unwritable reusable workflows `asanexample/trusted-ci/build-sign.yml` (build →
  push → cosign sign → SBOM) and `slsa-provenance.yml` (provenance), pinned to a commit SHA.
  Keyless OIDC → Fulcio → Rekor; signs the digest. Don't copy these steps into your repo.
- **Trust is registry-derived, no allow-list to edit.** Set `spec.repo` in your Product
  registry entry (`gitops/products/<team>/<product>.yaml`) to your app repo; the `policy`
  unit builds the per-product verify policy from it. The cert's `githubWorkflowRepository`
  extension gates the shared signer identity to your repo.
- Onboarding detail: `docs/runbooks/app-supply-chain-onboarding.md`; design:
  `docs/architecture/cosign-image-signing.md`.

## Minimal compliant Deployment

The canonical, maintained example is **`docs/examples/compliant-deployment.yaml`** — read
and adapt it (the New Product scaffolder emits the same shape). The essence:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-acme-store
  labels: { app.kubernetes.io/name: app-acme-store }   # team label is auto-injected
spec:
  replicas: 2
  selector: { matchLabels: { app: app-acme-store } }
  template:
    metadata: { labels: { app: app-acme-store } }
    spec:
      serviceAccountName: app-acme            # named SA (never default); Pod Identity binds AWS creds here
      automountServiceAccountToken: false     # (auto-injected if omitted)
      containers:
        - name: web
          image: 829808296602.dkr.ecr.us-east-1.amazonaws.com/team-acme/store-web:placeholder  # scoped, explicit tag, cosign-signed
          ports: [{ containerPort: 8080 }]
          resources:
            requests: { cpu: 100m, memory: 128Mi }   # requests AND limits, both required
            limits:   { cpu: 500m, memory: 512Mi }
          livenessProbe:  { httpGet: { path: /healthz, port: 8080 }, periodSeconds: 15 }
          readinessProbe: { httpGet: { path: /healthz, port: 8080 }, periodSeconds: 10 }
      # securityContext (allowPrivilegeEscalation:false, capabilities.drop:[ALL],
      # seccompProfile:RuntimeDefault) is auto-injected — don't set it.
```

## If a workload legitimately must violate a policy

That's a platform decision, not something to work around by weakening a policy to fit one
app. Follow `docs/runbooks/kyverno-break-glass.md`. The break-glass knobs are operator-side
(flip the `policy` unit's `validation_failure_action` / `verify_failure_action` /
`attest_failure_action` to `Audit`, or fail-open the webhooks) — never loosen the identity
trust. PlatformAdmin operates Kyverno; PlatformDeployer authors policies via GitOps (ADR-040).

## Regulated compliance tiers (not the current standard clusters)

The current platform/preprod clusters are `compliance_tier = standard`. On `hipaa`/`pci`
tiers, two more policies become Enforce — `runAsNonRoot: true` and
`readOnlyRootFilesystem: true` on every container (`require-pod-security-restricted`,
`require-ro-rootfs`). Don't add these pre-emptively on standard clusters.

## References

- `docs/architecture/kyverno-policy-catalog.md` — authoritative per-cluster policy catalog
- `docs/examples/compliant-deployment.yaml` — the maintained minimal compliant manifest
- `docs/runbooks/kyverno-break-glass.md` — exceptions / emergency procedure
- `docs/architecture/cosign-image-signing.md`, `docs/runbooks/app-supply-chain-onboarding.md` — signing/attestation
- `infra/modules/policy/policies-chart/templates/` — the actual ClusterPolicy sources
