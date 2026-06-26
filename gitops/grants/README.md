# AccessGrant claims

`AccessGrant` resources (product-scoped cross-team access, ADR-068) live here — one per file — and are synced to
the cluster by the **`grants` registry-sync** ArgoCD app (see `infra/modules/argocd-apps/delivery.tf`).

This directory is intentionally empty for now (no cross-team grants authored yet). It exists so the registry-sync
app has a **valid path to read**: an empty directory makes the app `Synced`/`Healthy` with zero resources, whereas
a *missing* directory makes it error with `app path does not exist` (which is exactly what was happening before
this file was added).
