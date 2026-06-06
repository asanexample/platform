# Platform rebuild from scratch

How to tear down and rebuild the AWS platform from nothing, using **platctl** (the orchestration CLI in
`cmd/platctl/`). Data loss is expected and acceptable — the success criterion is that the platform is fully
reconstructable from code. This runbook is the rebuild-specific procedure; for the full `platctl` command
reference see [`cmd/platctl/README.md`](../../cmd/platctl/README.md).

> **Identity note (ADR-053/059):** the identity stack (keycloak, keycloak-config, the gateway split, the ArgoCD
> OIDC cutover) is **rebuild-gated** — it has only ever been verified offline/ephemerally, never applied to a live
> cluster. The rebuild is the first real apply. Under the current **AWS Identity Center** upstream, group claims
> are empty (the membership gap), so SSO authenticates users but grants no group-based access yet — ArgoCD admin
> is via its local break-glass account until a group-emitting upstream lands.

## 0. Build platctl (it is NOT on your PATH by default)

`platctl` is a Go binary that must be built; bare `platctl` will be "command not found".

```bash
make build-platctl          # → ./bin/platctl
# or install on PATH:
make install-platctl        # → $GOPATH/bin/platctl (ensure $GOPATH/bin is on PATH)
```

This runbook uses `./bin/platctl`. Always **rebuild** before a rebuild run so the binary matches current code.

## 1. Pre-flight

### Tooling & access

- `tofu` (the `terraform_binary`), `terragrunt`, **`aws` CLI, and `kubectl`** installed; `./bin/platctl` built.
  (`aws` + `kubectl` back the providers' exec-auth and the keycloak-config port-forward; `kubectl` is the same
  binary `platctl validate` already uses.)
- `.platctl.yaml` present at the repo root (gitignored). Copy `.platctl.yaml.example` → `.platctl.yaml` and fill
  in account IDs / regions / validate config.
- `infra/live/aws/secrets.hcl` present (gitignored) and complete — account IDs, emails, and the SSO URLs/certs.
  See `secrets.hcl.example`.
- **AWS SSO** logged in for every profile the DAG uses: `aws sso login --profile management` (and `platform`,
  `preprod` if separate). Tokens expire — re-login if you see `SSOProviderInvalidToken`.
- **Tailscale — NOT required to deploy.** The deploy path reaches the cluster via the EKS API (public during
  bootstrap), and keycloak-config configures Keycloak via an in-cluster port-forward (§3) — no tailnet needed.
  Tailscale is still required for **human/browser** access to the internal services and for `platctl validate`'s
  internal-endpoint checks. (Day-2 config against a locked-down private cluster uses an SSM tunnel —
  `scripts/eks-tunnel.sh` — also without Tailscale.)

### State backend (only if truly from zero)

The S3 state bucket + DynamoDB lock table are bootstrapped once via the `state_bootstrap` unit with a local
backend, then state is migrated to S3 — see [ADR-006](../adrs/006-state-bootstrap-pattern.md). If the backend
already exists, skip this.

### Manual prerequisites (not automated)

`platctl bootstrap` pre-flight-checks the ones with a `manual_steps` entry (via `secret_exists`/`file_contains`)
and prompts if missing; the rest you must ensure yourself. For a from-scratch rebuild you need:

| Prerequisite | Where | Runbook |
| ------------ | ----- | ------- |
| Identity Center **SAML app for Dex** → `dex_sso_url`/`dex_sso_ca_data` (cert = **base64-of-PEM**) | secrets.hcl | [dex-sso.md](dex-sso.md) |
| Identity Center **SAML app for ArgoCD** → `argocd_sso_url`/`argocd_sso_ca_data` | secrets.hcl | [argocd-sso.md](argocd-sso.md) |
| Identity Center **SAML app for Keycloak** → `keycloak_sso_url`/`keycloak_sso_ca_data` (cert = **BARE base64 body**, differs from Dex) | secrets.hcl | [keycloak-sso.md](keycloak-sso.md) |
| **Cloudflare API token**, **Tailscale API key/OAuth** | Secrets Manager | (platctl manual_steps) |
| **Backstage GitHub App** → `platform/backstage/github-app` | Secrets Manager | [backstage-github-app.md](backstage-github-app.md) |
| **ECR images** (Backstage at the pinned SHA; app images) pushed | ECR | app CI |
| **ArgoCD `backstage` token** → `platform/argocd/backstage-token` | Secrets Manager | [backstage-argocd.md](backstage-argocd.md) — **minted after ArgoCD is up** (post-bootstrap or a resume pass) |

> **Gap to close:** `.platctl.yaml.example` only has `manual_steps` for cloudflare/tailscale/argocd-saml. Adding
> entries for the Keycloak/Dex SAML values (`file_contains` on secrets.hcl) and the Backstage GitHub App
> (`secret_exists`) would make bootstrap pre-flight catch them. Recommended follow-up.

### Preview the plan

```bash
./bin/platctl bootstrap --dry-run            # waves, manual steps, hooks, lockdown
./bin/platctl bootstrap --dry-run --env platform
```

## 2. Teardown (only when rebuilding an existing stack)

```bash
./bin/platctl teardown --dry-run             # reverse-DAG preview
./bin/platctl teardown                        # destroy (data loss expected/OK)
```

platctl runs an **unlock** phase first (re-applies `bootstrap_args`, e.g. re-enabling the EKS public endpoint so
the API is reachable for destroy), then `teardown_args` (e.g. `force_destroy=true`), skips empty-state units, and
destroys in reverse dependency order. If an SCP blocks a destroy (KMS keys, flow logs), see the platctl README
"SCP-blocked destroy" (state-rm the resource, then destroy). Teardown is resumable: `./bin/platctl teardown --resume`.

## 3. Bootstrap

```bash
./bin/platctl bootstrap                        # both envs, DAG order, parallel
# or: ./bin/platctl bootstrap --env platform
```

platctl auto-discovers the DAG, pre-flight-checks manual steps (prompts; `--yes` to skip), applies in waves,
then runs the **lockdown** phase (re-applies `platform/eks`/`preprod/eks` to disable the public endpoint, locks
down tailscale) and configures kubeconfig. Logs stream to `.platctl-logs/latest/`.

**Identity ordering (ADR-059), for reference:** `gateway` (foundational, early — no app deps) → `keycloak`
(self-owns its browser HTTPRoute on the gateway) → `keycloak-config`; separately `argocd → keycloak-config`;
`gateway-config` carries the remaining app routes.

### keycloak-config readiness (automatic, in-cluster — no Tailscale, no `--resume`)

`keycloak-config` configures Keycloak **in-cluster** via a kubectl **port-forward to the ClusterIP** — not the
Tailscale-fronted gateway — so the deploy path needs no tailnet and doesn't depend on the gateway/cert/NLB/DNS:

- The `keycloak` unit applies with **`helm_wait = true`** — its apply blocks until the Keycloak pod is Ready.
- The `keycloak-config` unit has a Terragrunt **`before_hook`** (`scripts/kc-portforward.sh up`) that opens a
  background `kubectl port-forward svc/keycloak` (reaching the cluster via the EKS API + the deployer role, on a
  throwaway kubeconfig), waits until Keycloak answers on `localhost:18080`, **then** applies — with the provider
  pointed at `http://localhost:18080`. An **`after_hook`** (`run_on_error`) tears the forward down.

So keycloak-config waits for its own in-cluster connection, then succeeds — deterministically. The provider talks
to localhost; the realm/SAML config still uses the canonical `https://keycloak.aws.refplat.org` (the `keycloak_url`
input). Prerequisite: **cluster API reachability**, which the rebuild already has (EKS endpoint public during
bootstrap; or an SSM tunnel for a private day-2 cluster) — **not** Tailscale. If the forward can't establish or
Keycloak never serves, the hook fails with a hint; fix and `./bin/platctl bootstrap --resume` (fallback only).

## 4. Validate

```bash
./bin/platctl validate                         # IAM phase, then infra: eks, cilium, gateway TLS, tailscale, dns, endpoints
./bin/platctl validate --env platform
./bin/platctl validate --check gateway,dns,tailscale
./bin/platctl status                           # last run's per-unit result
```

Then smoke-test SSO in a browser (over Tailscale): ArgoCD (`argocd.aws.refplat.org`) → "Log in via Keycloak";
Backstage; Grafana. Remember: under AWS IdC the group claims are empty, so expect authenticated-but-unauthorized
for SSO users — use the ArgoCD local `admin` (break-glass) for admin actions until membership lands.

## 5. Known gotchas

- **`platctl: command not found`** → it's not on PATH; build it (`make build-platctl`) and run `./bin/platctl`.
- **Stale `.platctl-state.json`** from a prior run → `--resume` to continue, or `rm .platctl-state.json` to start
  fresh (bootstrap will also prompt).
- **`keycloak-config` readiness** is gated automatically (helm_wait + the `kc-portforward.sh` before_hook, §3) —
  no `--resume` on the happy path, and no Tailscale. If the port-forward can't establish, it's a real problem
  (cluster API unreachable — confirm the EKS endpoint is public during bootstrap, or use an SSM tunnel): fix it,
  then `--resume`. A leaked `kubectl port-forward` (after a crash) can be cleared with
  `bash scripts/kc-portforward.sh down <cluster> 18080`.
- **Expired SSO** mid-run → `aws sso login --profile <p>`, then `--resume`.
- **State lock** → `cd <unit-dir> && terragrunt force-unlock <id>` (platctl README).
- The **gateway/keycloak split is a fresh apply** on a clean rebuild (the Gateway is created by the `gateway`
  unit, routes by `gateway-config`/`keycloak`); do not apply it piecemeal to a live cluster — relocating the
  Gateway there is destroy+recreate.
