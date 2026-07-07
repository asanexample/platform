# Portal glossary — the shared vocabulary

A quick-lookup for the terms that recur across the [learning modules](README.md). This is **not** where
they're taught — each module grounds its terms in context, just-in-time, which is what makes them stick.
This is the place to *look one up later*, with a link to the canonical doc and (per section) the module
that teaches it. Terms specific to one subsystem live in that module's own Reference; this covers the
cross-cutting substrate and domain vocabulary.

## The domain model — *taught in [the domain model](domain-model/orientation.md)*

- **Team** — the owner: an SSO group plus an *envelope*. Owns Products; owns no infra itself.
- **Product** — a deployable a Team builds; maps to exactly one repo. Owns Services.
- **Service** — a single running component of a Product (a web frontend, an API).
- **Environment** — a Product at a Stage (`= one namespace`); the unit of deployment.
- **Customer** — an external consumer; a per-customer prod Environment is dedicated to one.
- **Stage** — a promotion rung (`dev` / `test` / `staging` / `uat` / `prod`) — *not* a place.
- **Envelope** — the bounds a Team declares: allowed tiers/stages and quota cap enforced at admission; budget currently audit-only (ADR-091 Phase C, not yet flipped to Enforce).
- **Tier** — the hardening/compliance level (`standard`, `pci`, `hipaa`, …); a *floor*, not a fixed level.

## Kubernetes

- **Cluster** — the pool of machines Kubernetes runs apps on. ([Kubernetes](https://kubernetes.io/docs/concepts/overview/components/))
- **Namespace** — an isolated slice of a cluster; one Environment = one namespace. ([Kubernetes](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/))
- **Pod** — a running instance of your app (one or more containers). ([Kubernetes](https://kubernetes.io/docs/concepts/workloads/pods/))
- **Custom resource (CR / CRD)** — a record type the platform defines and the cluster stores + acts on. ([Kubernetes](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/))
- **Admission** — the checkpoint every resource crosses on its way into the cluster (the "bouncer at the door"). ([Kubernetes](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/))
- **RBAC / RoleBinding** — who may do what in the cluster. ([Kubernetes](https://kubernetes.io/docs/reference/access-authn-authz/rbac/))
- **ServiceAccount** — a pod's in-cluster identity. ([Kubernetes](https://kubernetes.io/docs/concepts/security/service-accounts/))

## Crossplane — the provisioning engine — *taught in [the Environment API](environment-api/orientation.md)*

- **Composition** — the recipe that turns one claim into its resources. ([Crossplane](https://docs.crossplane.io/latest/composition/compositions/))
- **XRD** — the schema that defines a custom claim type (e.g. `XEnvironment`).
- **XR / claim** — an instance of that type; your statement of desired state.
- **Managed resource (MR)** — one real thing Crossplane creates *and continuously watches*. ([Crossplane](https://docs.crossplane.io/latest/managed-resources/))
- **Provider** — a plugin that lets Crossplane talk to an external API (AWS, Kubernetes).
- **ProviderConfig** — which credentials/role a provider uses.
- **EnvironmentConfig** — per-cluster constants injected into a Composition. ([Crossplane](https://docs.crossplane.io/latest/composition/environment-configs/))
- **Reconcile / level-triggered** — continuously driving *actual* state toward *desired*; why it self-heals. ([Kubernetes](https://kubernetes.io/docs/concepts/architecture/controller/))

## AWS

- **EKS** — AWS's managed Kubernetes; the clusters run on it. ([AWS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html))
- **ECR** — AWS's container image registry. ([AWS](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html))
- **IAM** — AWS identity & access (roles, policies). ([AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html))
- **Pod Identity** — how a pod gets an AWS role via its ServiceAccount, no static keys. ([AWS](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html))

## Platform tools

- **Kyverno** — the policy engine that enforces the rules at admission. ([docs](https://kyverno.io/docs/)) *taught in [Policy & admission](policy/orientation.md)*
- **ArgoCD** — the GitOps engine that syncs cluster state from git. ([docs](https://argo-cd.readthedocs.io/en/stable/)) *taught in [Delivery](delivery/orientation.md)*
- **Cilium** — the platform's CNI (pod networking + the gateway). ([docs](https://docs.cilium.io/en/stable/overview/intro/))
- **cosign** — signs and verifies container images. ([docs](https://docs.sigstore.dev/cosign/signing/overview/)) *taught in [Supply chain](supply-chain/orientation.md)*
