# Onboarding Guide

Welcome. This guide gets a **platform / DevEx engineer** productive on the repository: installing the
toolchain, understanding the layout, deploying the stack, and making your first change. (If you're a
**developer shipping an app**, you don't deploy infrastructure — you use the self-service paved road; jump to
[The developer paved road](#the-developer-paved-road).)

> **New here?** Skim the [README](../README.md) for the big picture, the [Glossary](glossary.md) for the
> vocabulary, and [Identity & SSO](architecture/identity-and-sso.md) for how login/permissions work (the part
> most people find confusing). For "I can't log in," go straight to
> [SSO Troubleshooting](runbooks/identity-sso-troubleshooting.md).

---

## Prerequisites

### Toolchain — one source of truth

The CLI tool versions are pinned canonically in [`/.tool-versions`](../.tool-versions) — read by local dev
(**mise** or asdf), CI, and the self-hosted runner image alike, so nothing drifts. **Don't hand-install
minimums; install the exact pins:**

```bash
mise install        # (or: asdf install) — reads /.tool-versions
```

That installs the pinned **OpenTofu 1.12.1**, **Terragrunt 1.0.7**, **kubectl 1.35.5**, **Helm 3.21.0**, and
**AWS CLI 2.35.1**. (kubectl tracks the cluster's minor to stay within the ±1 skew policy; bump versions in
`/.tool-versions` and everything follows.) You'll also want **Git** ≥ 2.30 and, for the CLI, the Go toolchain
to build `platctl` (`make build-platctl` → `./bin/platctl`).

### AWS access (SSO via IAM Identity Center)

Access is via AWS IAM Identity Center. The profile that matters for almost everything is **`management`** —
Terragrunt and `platctl` both run as it (the backend assumes `TerraformStateAccess`, and the providers assume
`PlatformDeployer` from there; see [root.hcl](../infra/root.hcl)). Add to `~/.aws/config`:

```ini
[sso-session refplat]
sso_start_url = https://d-XXXXXXXXXX.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile management]
sso_session = refplat
sso_account_id = <MGMT_ACCOUNT_ID>
sso_role_name = <your Identity Center permission set>   # see architecture/identity-and-sso.md
```

Log in and verify:

```bash
aws sso login --profile management
AWS_PROFILE=management aws sts get-caller-identity
```

> **Heads-up:** a bare shell is *not* authenticated — almost every command here needs `AWS_PROFILE=management`
> (or it falls back to your default identity and 403s on `PlatformDeployer`). SSO sessions expire (≈ over a
> weekend) → SOPS/KMS decrypt fails → re-run `aws sso login --profile management`.

For `kubectl` against the **private** clusters, see [EKS Cluster Access](runbooks/eks-cluster-access.md):
`platctl kubeconfig` writes the contexts (kubectl assumes **PlatformAdmin** — operate/debug, not author —
[ADR-040](adrs/040-platform-engineer-access-model.md)), and you reach the private API over **Tailscale**.

### Web consoles (ArgoCD, Backstage, Grafana)

All three are served Tailscale-only and authenticate against **Keycloak** (OIDC — the platform's IdP of
record; Dex + per-app SAML are retired, [ADR-053](adrs/053-identity-and-cross-system-authorization-strategy.md)/[059](adrs/059-identity-topology-pluggable-idp-seam.md)):

| Console | URL | Access |
|---|---|---|
| **ArgoCD** | `https://argocd.aws.refplat.org` | "Log in via Keycloak" → team-scoped RBAC by group ([ArgoCD SSO](runbooks/argocd-sso.md)) |
| **Backstage** | `https://backstage.aws.refplat.org` | The developer portal — catalog + software templates ([ADR-051](adrs/051-backstage-developer-portal.md)) |
| **Grafana** | `https://grafana.aws.refplat.org` | Keycloak SSO; `platform-admins` → Admin, else Viewer |

Each keeps a local `admin` account as **break-glass only**. For ArgoCD's:

```bash
kubectl --context platform -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## Repository structure

```text
.
├── cmd/platctl/                  # The platctl orchestration CLI (Go, ADR-038)
├── gitops/                       # SOURCE OF TRUTH: Team / Product / Environment / Release registries
├── docs/                         # User-facing docs (you are here) — adrs/ architecture/ runbooks/ …
├── infra/
│   ├── root.hcl                  # Root Terragrunt config: remote state (S3), providers, role assumption
│   ├── live/aws/                 # Terragrunt live configs (171 units; AWS is the only cloud today)
│   │   ├── _base.hcl             # Composer: loads the config layers + safety assertions
│   │   ├── _versions.hcl         # Module source paths + Helm version pins
│   │   ├── common.hcl            # Cloud-wide defaults; loads secrets.hcl (gitignored)
│   │   ├── mgmt/global/          # Management account (Organizations, SCPs, state, Identity Center)
│   │   ├── platform/us-east-1/   # Platform account — the hub cluster + shared services
│   │   ├── preprod/us-east-1/    # Preprod account — environment workloads
│   │   ├── prod/  & test/        # Prod (networking only) and the Terratest sandbox
│   ├── modules/                  # ~60 reusable OpenTofu modules
│   │   ├── aws/                  # 20 AWS-specific (organizations, eks, networking, ecr, tgw, …)
│   │   ├── cloudflare/           # DNS delegation
│   │   └── (cloud-agnostic)      # argocd, crossplane, policy, keycloak, backstage, cilium,
│   │                             #   17× observability-*, secret-stores, tailscale, falco, …
│   └── tests/                    # Terratest (Go) module integration tests
└── infra/docs/                   # Infrastructure design docs (numbered 00–20)
```

The git-native **`gitops/` registries are the source of truth** — `argocd-apps`, `policy`, and `github-oidc`
*derive* delivery and supply-chain policy from them (the old `teams.hcl` is gone). See
[Crossplane Environment API](architecture/crossplane-environment-api.md).

---

## Configuration hierarchy

Terragrunt composes inputs through layers, each overriding the broader one above it (`_versions.hcl` and
`_base.hcl` are supporting files loaded by the composer, not layers — see
[config-hierarchy.md](architecture/config-hierarchy.md)):

1. **Root** (`infra/root.hcl`) — remote state, providers, role assumption
2. **Cloud** (`common.hcl`) — cloud-wide defaults, loads `secrets.hcl`, account mapping, `cost_profile`
3. **Environment** (`{env}/env.hcl`) — account ID, env tags, feature toggles
4. **Region / network** (`{env}/{region}/region.hcl` + `network.hcl`) — region, CIDRs
5. **Workload** (`…/{workload}/workload.hcl`) — workload name, compliance tier
6. **Unit** (`…/{unit}/terragrunt.hcl`) — final inputs + dependencies

Units pull all of it via `include "base"`. Tags merge across layers (narrower wins); `_base.hcl` also asserts
the directory path matches the configured environment and account ID. Sensitive values (account IDs, emails)
live in `infra/live/aws/secrets.hcl` (gitignored — see `secrets.hcl.example`).

---

## Deploying the stack

**The preferred path is `platctl bootstrap`** — it auto-discovers all 171 units, applies them in dependency
order with parallelism, handles the private-endpoint bootstrap problem (temporarily enables public API access,
locks it down once Tailscale is up), runs post-apply hooks, and is **resumable**. The canonical from-scratch
procedure (including the recovery escape hatches) is
[platform-rebuild-from-scratch.md](runbooks/platform-rebuild-from-scratch.md). The short version:

```bash
make build-platctl                    # → ./bin/platctl
aws sso login --profile management
./bin/platctl bootstrap --dry-run     # preview the waves, manual steps, hooks, lockdown
./bin/platctl bootstrap               # or --resume to pick up after a failure
```

### Manual prerequisites (not automated)

A few secrets/identities must exist first; `platctl` pre-flight-checks the ones with a `manual_steps` entry:

| Prerequisite | Stored at | Runbook |
|---|---|---|
| **Cloudflare API token**, **Tailscale API key/OAuth** | Secrets Manager | (platctl `manual_steps`) |
| **Backstage GitHub App** (read-only discovery) | `platform/backstage/github-app` | [backstage-github-app.md](runbooks/backstage-github-app.md) |
| **Backstage Scaffolder GitHub App** (write) | `platform/backstage/scaffolder-github-app` | [backstage-scaffolder-github-app.md](runbooks/backstage-scaffolder-github-app.md) |
| **ARC runner GitHub App** (self-hosted runners) | `platform/gha-runner-controller/github-app` | [arc-github-app.md](runbooks/arc-github-app.md) |

Identity is **Keycloak** (the realm + clients are provisioned by the `keycloak-config` unit; no manual SAML app
to create). The ArgoCD↔Backstage token is auto-minted by a bootstrap hook.

### The two foundational units come first

On a true greenfield, two management-account units precede `platctl` (the state backend must exist before any
remote-state unit, and Organizations creates the accounts):

```bash
# 1. State backend (local backend — it's the chicken-and-egg root)
cd infra/live/aws/mgmt/global/state-bootstrap
AWS_PROFILE=management terragrunt apply

# 2. AWS Organizations (OUs + member accounts + SCPs) — now stored in the remote backend
cd ../organizations
AWS_PROFILE=management terragrunt apply
```

To tear down: `./bin/platctl teardown`.

---

## How to make a change

Edit → plan → review → apply.

```bash
# 1. EDIT — module logic in infra/modules/, environment inputs in infra/live/
# 2. PLAN — from the unit directory
cd infra/live/aws/platform/us-east-1/platform/<unit>
AWS_PROFILE=management terragrunt plan          # scan for -, -/+ (destroy/replace), policy/IAM changes

# 3. REVIEW — open a PR (CI runs fmt/validate/TFLint/Kyverno tests/Trivy/Semgrep). Paste the plan.
# 4. APPLY — after approval
AWS_PROFILE=management terragrunt apply
```

For changes spanning many units, `terragrunt run --all plan` from a parent directory first, then
`run --all apply` — **with caution** (note: it's `run --all`, the modern syntax, not the old `run-all`).
Enable the pre-commit hooks (`git config core.hooksPath .githooks`) — they run `tofu fmt`, `terragrunt
hclfmt`, and `tofu validate` on staged files.

---

## The developer paved road

You generally **won't** hand-write Kubernetes manifests or touch Terragrunt to ship an app — that's the whole
point. The self-service flow ([ADR-046](adrs/046-back-stack-for-developer-self-service.md)/[067](adrs/067-idp-domain-model.md)):

1. In **Backstage**, pick the *New Product* template (team, product, stage). The scaffolder opens a **gated
   PR** adding a `Product` registry entry + an `XEnvironment` claim (and a repo from the golden-path skeleton).
2. On merge, **ArgoCD** applies the claim and a **Crossplane Composition** provisions the whole environment —
   namespace (`<team>-<product>-<env>`, e.g. `alpha-shop-dev`), RBAC, quotas, default-deny networking, an ECR
   repo (`team-<team>/<product>-<svc>`), scoped IAM via Pod Identity, developer access, and per-product policy.
3. App CI (a thin caller of the shared `trusted-ci` workflows) builds, **cosign-signs**, attaches an SBOM +
   SLSA provenance, and pins the deploy manifest to the signed digest. **Kyverno verifies it at admission.**

Workloads in environment namespaces must be policy-compliant or they're rejected at admission — the rules are
summarized in [CLAUDE.md](../CLAUDE.md#authoring-policy-compliant-workloads-kyverno). Details:
[Deploy App to Preprod](runbooks/deploy-app-preprod.md) · [Environment Onboarding](runbooks/environment-onboarding.md).

---

## Where to find things

| I want to… | Go to… |
|---|---|
| The big picture | [README](../README.md) |
| Understand **why** a decision was made | [`docs/adrs/`](adrs/) — 77 ADRs |
| Understand **how** the system is designed | [`docs/architecture/`](architecture/) + [`infra/docs/`](../infra/docs/) |
| Follow a **procedure** | [`docs/runbooks/`](runbooks/) |
| Configure/deploy a **module** | [User Guide](user-guide.md) + module READMEs |
| The self-service / environment model | [Crossplane Environment API](architecture/crossplane-environment-api.md) |
| The signed supply chain | [Supply-Chain Overview](architecture/supply-chain-overview.md) |
| What's running in observability | [Observability Current State](architecture/observability-current-state.md) |
| Prove **compliance** | [`docs/compliance/`](compliance/) |
| Debug a **problem** | [`docs/troubleshooting/`](troubleshooting/) |

---

## Common first-day tasks

```bash
# Which identity am I?
AWS_PROFILE=management aws sts get-caller-identity

# Plan / inspect a unit
cd infra/live/aws/platform/us-east-1/platform/<unit>
AWS_PROFILE=management terragrunt plan
AWS_PROFILE=management terragrunt state list

# Configure kubectl, then look around a cluster (over Tailscale)
platctl kubeconfig
kubectl --context platform get pods -A
kubectl --context preprod get ns | grep -E '<team>-'   # environment namespaces

# Validate the deployed platform
platctl validate                       # or: --env platform / --check tailscale

# Read an enforced SCP
AWS_PROFILE=management terragrunt state show \
  'aws_organizations_policy.this["baseline-guardrails"]'   # from mgmt/global/organizations
```

---

## Next steps

1. Read the [User Guide](user-guide.md) for module configuration and day-2 operations.
2. Skim the [ADRs](adrs/) for the reasoning behind the key choices (and what was rejected).
3. Explore the [infrastructure design docs](../infra/docs/) (`00`–`20`) for deep-dives.
4. Browse [`docs/runbooks/`](runbooks/) for procedures relevant to your work.
