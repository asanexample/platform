# Screenshot capture checklist — environment-api

> Meta-doc for the author. These couldn't be captured automatically (Backstage/ArgoCD are Tailscale-only,
> Keycloak-gated, and unreachable from tooling). Capture them by hand, drop the PNG in `images/`, then
> replace the matching `> 📸 **Screenshot:** …` blockquote in the doc with `![alt](images/<name>.png)`.

## 1. ArgoCD — the `environments` app syncing the claim

- **File / save as:** `images/argocd-environments-alpha-shop-dev.png`
- **Used in:** `orientation.md`, step 2 ("The claim reaches the cluster").
- **App:** ArgoCD UI (Tailscale + SSO). The platform ArgoCD that owns the `environments` Application.
- **Nav:** Applications → open **`environments`** → in the resource tree, locate the `XEnvironment`
  node named **`alpha-shop-dev`**.
- **Frame:** the `alpha-shop-dev` node showing **Synced / Healthy**, ideally with a few of its child
  resources visible in the tree. The point of the shot is "this came from git, nothing applied by hand."

## 2. Backstage — the catalog's view of the environment

- **File / save as:** `images/backstage-catalog-alpha-shop-dev.png`
- **Used in:** `orientation.md`, "Explain it back" (the capstone).
- **App:** Backstage — `https://backstage.aws.refplat.org` (Tailscale + Keycloak SSO).
- **Nav:** Catalog → filter kind **System** → open **`alpha-shop-dev`**.
- **Frame:** the System entity page with its **Resources / Relations** panel visible — you want the
  namespace, the `team-alpha/shop-web` ECR repository, the `Pod-alpha-shop-dev-web` IAM role, and the
  `restrict-images` / `restrict-route-hostnames` policies showing as owned resources. The point is "the
  platform sees the footprint you built."

## Tips

- Light theme reads better in docs.
- Crop tight to the relevant panel; avoid capturing the whole browser chrome.
- If a real value looks sensitive, it isn't here — team/product/stage names and ARNs in this repo are
  already public (workforce/infra identifiers, not customer data).
