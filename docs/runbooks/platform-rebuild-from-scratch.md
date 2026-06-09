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

> **⚠️ Identity prereqs UPDATED 2026-06-09 — Dex + per-app SAML retired.** Keycloak is now the app-facing IdP
> (ADR-053/059); **ArgoCD and Backstage sign in via Keycloak OIDC**, not their own Identity Center SAML apps,
> and **Dex + oauth2-proxy are gone** (B5). So the old Dex/ArgoCD SAML rows below are removed. Keycloak runs as
> the **IdP of record by default** — `keycloak-config` seeds the realm users — so **no Identity Center SAML app
> is required** for a standard rebuild; an upstream SAML/OIDC broker app is **optional** and only needed if you
> federate Keycloak to a corporate IdP.

| Prerequisite | Where | Runbook |
| ------------ | ----- | ------- |
| *(optional)* Identity Center **SAML/OIDC app for Keycloak upstream federation** → `keycloak_sso_url`/`keycloak_sso_ca_data` — only if federating to a corporate IdP; omit for the default standalone (seeded users) | secrets.hcl | [keycloak-sso.md](keycloak-sso.md) |
| **Cloudflare API token**, **Tailscale API key/OAuth** | Secrets Manager | (platctl manual_steps) |
| **Backstage GitHub App** (read-only discovery) → `platform/backstage/github-app` | Secrets Manager | [backstage-github-app.md](backstage-github-app.md) |
| *(Phase 3)* **Backstage Scaffolder GitHub App** (write) → `platform/backstage/scaffolder-github-app` | Secrets Manager | [backstage-scaffolder-github-app.md](backstage-scaffolder-github-app.md) |
| **ECR images** (Backstage at the pinned SHA; app images) pushed | ECR | app CI |
| **ArgoCD `backstage` token** → `platform/argocd/backstage-token` | Secrets Manager | [backstage-argocd.md](backstage-argocd.md) — **minted after ArgoCD is up** (post-bootstrap or a resume pass) |

> **Gap to close:** `.platctl.yaml.example` only has `manual_steps` for cloudflare/tailscale. Adding entries for
> the (optional) Keycloak upstream SAML values (`file_contains` on secrets.hcl) and the Backstage GitHub App(s)
> (`secret_exists`) would make bootstrap pre-flight catch them. Recommended follow-up.

### First-rebuild gotchas (learned 2026-06-07 — the first real from-scratch bootstrap)

Do these / be aware of these before/at bootstrap; each cost a `--resume` cycle the first time:

1. **Bootstrap `iam-roles` via break-glass FIRST.** `iam-roles` creates `PlatformDeployer` (which every other unit
   assumes), so it can't run via the deployer — it runs raw as your SSO admin, which the `DenyTeamTagTampering`
   SCP blocks from `iam:TagRole`. Run **`./scripts/bootstrap-iam-roles.sh`** (assumes the SCP-exempt
   `OrganizationAccountAccessRole`) before `platctl bootstrap`, then bootstrap/resume normally.
2. **Disable Tailscale DNS on the runner.** If you're connected to the tailnet, its split-DNS
   (`*.eks.amazonaws.com → VPC resolver`) hijacks EKS-API resolution but the subnet router isn't up yet →
   keycloak/dex/tailscale fail with `i/o timeout`. Run **`sudo tailscale set --accept-dns=false`** during the
   bootstrap (re-enable after). *(Durable fix TODO: teardown should clear the tailnet split-DNS.)*
3. **SSO token can corrupt under concurrency.** Parallel units refreshing the SSO token at once can clobber
   `~/.aws/sso/cache` → `get_aws_account_id() ... failed to parse cached SSO token file`. Just
   **`aws sso login`** again and `--resume`. *(Durable fix TODO: platctl should pre-warm creds before the waves.)*
4. **Backstage image must be re-pushed.** ECR is force-deleted on teardown, so the pinned Backstage image is gone.
   After the early `ecr`/`github-oidc` waves recreate the repo + OIDC role, merge the Backstage build → it pushes
   a fresh (arm64) image; bump `backstage` unit `image_tag` to that SHA.
5. **preprod `policy` ↔ `crossplane` circular dep — FIXED.** Two policies matched Crossplane CRDs (`XTenant`,
   `ProviderConfig`) that don't exist until crossplane deploys — but crossplane depends on policy. Kyverno churned
   its webhook config on the missing CRDs and the bulk policy install couldn't fully converge on the leaner preprod.
   `restrict-tenant-envelope`/`restrict-tenant-control-plane` now live in the **crossplane** module
   (`charts/tenant-policies`, a `helm_release` gated on `enable_tenant_api`, installed after `crossplane_teams`), so
   every CRD they match already exists at install time — no churn. The `policy` unit no longer ships them (and its
   `atomic = false` from the same incident stays, as defence-in-depth for the remaining bulk install).

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
destroys in reverse dependency order. Resumable: `./bin/platctl teardown --resume`.

**Scope (verify before destroying):** platctl only manages the `platform` + `preprod` environments — it does
**not** touch the management account (org, Identity Center, the **S3 state backend**) or test. Confirm the
`--dry-run` unit list contains only `platform/*` + `preprod/*`; the state backend must survive (it holds the
state the rebuild reads from). **Your real `.platctl.yaml` must carry the `teardown_args` from
`.platctl.yaml.example`** (force_destroy/force_delete for route53, ecr, mimir, cloudtrail) or those units won't
destroy.

**Automated finalizer/drain cleanup (the first live teardown surfaced these; now durable in-module).** Several
controller-managed resources used to hang `terraform destroy`/helm-uninstall because they outlive the controller
being torn down — two sub-classes: (a) **CRs with a controller finalizer** the controller can no longer remove,
and (b) **`Succeeded` pods stuck `Terminating` with no finalizer** (the kubelet never confirms them) that pin
their `pvc-protection` PVCs and so block namespace termination. Each module now runs a `when = destroy` step that
self-authenticates to the cluster (`scripts/k8s-finalizer-clear.sh` — `aws eks update-kubeconfig` + the deployer
role; the old bare `kubectl patch` silently no-op'd with no context) and drains them **before** the delete:

- **tailscale** (`crd_finalizer_cleanup`) — the subnet-router `Connector`/`ProxyClass`: delete + clear finalizers
  so the manifest delete doesn't time out (the observed `Timed out waiting for ... subnet-router`).
- **crossplane** (`crd_finalizer_cleanup`) — Provider/Function/XRD/Composition/ProviderConfig/Usage CRs: delete +
  force-clear before the helm uninstalls, which otherwise hit `context deadline exceeded` on the async drain.
- **backstage** (`namespace_drain`) — delete the CNPG `Cluster` + force-evict stuck pods so the namespace doesn't
  hang ~5m in `Terminating`.
- **observability** (`namespace_drain`) — delete the prometheus/mimir/alertmanager StatefulSets (so pods can't
  recreate) + force-evict the stuck `Succeeded` pods; same namespace-hang symptom.

> The drains evict **pods only**, never PVCs: force-clearing a PVC's finalizer orphans its EBS volume (bypasses
> the CSI delete). Evicting the pod releases `pvc-protection`, so the namespace-controller deletes the PVC through
> CSI (still up at that point per the DAG), which cleans the EBS properly.

The helper takes `[--delete]` (delete-then-clear, for resources nothing else removes) and is bash-3.2-safe; it
enumerates names before patching (`kubectl patch` has no `--all`). It can also be run **manually** to unstick a
live teardown mid-flight, e.g.:
`bash scripts/k8s-finalizer-clear.sh --delete <cluster> <region> <deployer-role-arn> - connectors.tailscale.com`.

**Supervise the first teardown anyway.** Resumable, data-loss OK. Remaining watch list:

- **keycloak-config** — destroys via the port-forward while Keycloak is still up; only fails if Keycloak is
  *already* gone (a re-run) → `cd` the unit + `terragrunt state rm 'keycloak_*'`, then continue.
- **State lock** (`Error acquiring the state lock`, DynamoDB) — locks are per-unit, so this is a stale lock from
  an interrupted/earlier run, not contention: `terragrunt force-unlock -force <id> --working-dir <unit-dir>`, then
  `--resume`. (Get the id from the DynamoDB lock item's `Info.ID`.)
- **Cilium Gateway NLB → `networking` `DependencyViolation`** — now automated. The internal NLB
  (`kubernetes.io/service-name: default/cilium-gateway-platform-gateway`) is created by the in-cluster
  cloud-controller, so once `eks` is destroyed nothing can delete it; its ENIs then block subnet/VPC deletion. The
  `networking` unit has a **pre-destroy hook** (`before_hook "sweep_orphaned_lbs"` → `scripts/vpc-orphan-lb-sweep.sh`)
  that deletes any k8s-tagged LB in the VPC and waits for its ENIs to release before `terraform destroy` runs.
  Manual fallback if it's ever bypassed: find the LB by the `kubernetes.io/service-name` tag, `elbv2
  delete-load-balancer`, wait for ENIs to clear, then `--resume`.
- **Orphaned EBS backstop** — the drains avoid it, but if any `available` volumes remain post-teardown:
  `aws ec2 describe-volumes --filters Name=status,Values=available` then `delete-volume` each (data-loss OK).
- **Kyverno** (`policy`) — confirm its destroy removed the `*WebhookConfiguration`s; a dangling
  `failurePolicy=Fail` webhook would block later API ops.
- **KMS** keys enter a 7–30 day deletion window — expected, not a blocker (key is ID-based; alias is deleted), so
  the rebuild is unaffected.
- **SCP-blocked** resources (KMS, flow logs) are auto-handled; if one slips through, see the platctl README
  "SCP-blocked destroy" (state-rm + manual delete), then `--resume`.

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
