# Runbook: Backstage ArgoCD plugin — read-only token

The Backstage portal's ArgoCD plugin (Phase 2.4b, `@roadiehq/backstage-plugin-argo-cd`) reads our self-hosted
ArgoCD **read-only** to show per-Component sync/health + deployment history. It authenticates with an ArgoCD API
token for a dedicated, read-only local account (`backstage`). ADR-051: **read-only, never admin.**

## How it fits together

```text
Backstage backend (backstage ns)
  └─ argocd.appLocatorMethods[].instances[].token = ${ARGOCD_AUTH_TOKEN}
       │  (injected by infra/modules/backstage from the K8s secret backstage-argocd-token)
       └─ ExternalSecret ← AWS Secrets Manager: platform/argocd/backstage-token (key `token`)
  └─ url http://argocd-server.argocd.svc      (in-cluster, HTTP — server.insecure=true)
```

- The **account + RBAC** are declarative (argocd unit `argocd_cm_extra."accounts.backstage" = "apiKey"` +
  `rbac_policy_csv` line `g, backstage, role:readonly`).
- The **token** is minted out-of-band (ArgoCD mints it; there is no ArgoCD Terraform provider in this repo —
  same pattern as the GitHub App / repo-creds PAT) and stored in Secrets Manager.

## Automated by `platctl bootstrap` (the normal path)

`platctl bootstrap` re-mints this token automatically via the `argocd_account_token` hook on the `platform/argocd`
unit (`.platctl.yaml`). The hook runs right after ArgoCD applies — an **early** wave, before `backstage` — so a
valid token is in Secrets Manager before backstage's ExternalSecret first syncs (no restart / ESO force-refresh,
which the operate-only PlatformAdmin can't do). It is **idempotent**: it validates the current token first
(`argocd account get-user-info`) and re-mints only when the token is missing or invalid, so a rebuild heals the
stale-signing-key problem while incremental applies are no-ops. Failures warn but never fail the bootstrap.

The manual steps below are the **fallback** — for a live fix outside a bootstrap, or if the hook is disabled.

## Manual mint (fallback)

Prereq: the argocd unit has been applied with the `backstage` account + RBAC (above). Do this over the tailnet.

```bash
# 1. Log in to ArgoCD as admin (admin.enabled=true; password in the argocd-initial-admin-secret K8s secret).
ADMIN_PW=$(AWS_PROFILE=platform kubectl --context platform -n argocd \
  get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login argocd.aws.refplat.org --username admin --password "$ADMIN_PW"

# 2. Confirm the read-only account exists (apiKey capability).
argocd account get --account backstage          # capabilities: apiKey

# 3. Mint a token for it (no expiry; read-only via RBAC role:readonly).
TOKEN=$(argocd account generate-token --account backstage)

# 4. Store it in Secrets Manager (key `token`).
AWS_PROFILE=platform aws secretsmanager create-secret \
  --name platform/argocd/backstage-token --region us-east-1 \
  --secret-string "{\"token\":\"$TOKEN\"}" \
  || AWS_PROFILE=platform aws secretsmanager put-secret-value \
       --secret-id platform/argocd/backstage-token --region us-east-1 \
       --secret-string "{\"token\":\"$TOKEN\"}"
```

The backstage module's ExternalSecret syncs it into the `backstage-argocd-token` K8s secret → `ARGOCD_AUTH_TOKEN`.

## Verify

```bash
# Token is read-only: list works, mutate is denied.
ARGOCD_AUTH_TOKEN=$TOKEN argocd app list --server argocd.aws.refplat.org   # OK
ARGOCD_AUTH_TOKEN=$TOKEN argocd app sync alpha-demo --server argocd.aws.refplat.org  # PermissionDenied (expected)
```

In the portal: a Component with the `argocd/app-selector` annotation (e.g. `app-alpha`) shows the ArgoCD
overview + history cards. Backstage backend logs show no 401/403 from ArgoCD.

## ⚠️ Token revoked after an `argocd` apply (the one gotcha)

ArgoCD records the minted token's id in the `argocd-cm` ConfigMap (`accounts.backstage.tokens`). That ConfigMap is
also managed by the argocd unit's Helm release. Helm's 3-way merge **normally preserves** this runtime-added key,
so the token survives `argocd` applies — **but** if an apply ever drops it, the ArgoCD cards start returning
**401** (backend logs show it). Fix = **re-mint and update the secret** (steps 3–4 above); the ExternalSecret
re-syncs within its refresh interval (1h) — or force it sooner by deleting the `backstage-argocd-token` secret (ESO
recreates it) or `kubectl annotate externalsecret`.

## Rotation

The token does not expire. To rotate: re-mint (steps 3–4) and optionally revoke the old one
(`argocd account delete-token --account backstage --id <id>`; list ids with `argocd account get --account backstage`).
