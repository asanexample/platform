# Tutorial: render your first environment

> **⚠️ Preview — provisional until the learning sandbox is live**
>
> The full hands-on experience — apply a claim, watch ArgoCD sync it, delete a resource and watch it
> self-heal on a real cluster — needs a learning sandbox that's on the roadmap but not built yet. Until
> it lands, this tutorial runs entirely offline with `crossplane render`: no cluster, no Tailscale, no
> AWS, nothing you can break. You still get the real footprint and the real edit → render → diff loop.
> The steps marked 🔒 (sandbox) are the ones that light up once the sandbox ships.

You'll render a real environment on your laptop, read its footprint, then change it twice and watch the
output move. About 15 minutes, entirely local. Assumes you've read [the orientation](orientation.md).

## Before you start

- The `crossplane` CLI — check with `crossplane version` (you want both a client and a server line).
- Docker running — `crossplane render` runs the pipeline functions in containers.
- The platform repo checked out. Every command below runs from the Environment Composition's test harness:

```console
cd infra/modules/crossplane/.environment-api-tests
```

## 1. Render your first environment

The harness ships example claims under `environments/`. Render the `demo-dev` one — the `alpha` team's
`demo` product, in `dev`:

```console
crossplane render environments/demo-dev.yaml ../charts/environment-api/files/composition.yaml \
  render/functions.yaml --extra-resources render/environmentconfig.yaml
```

You'll see a stream of YAML documents: the whole footprint that one claim produces. It's the same set the
platform would create on a cluster — you're just seeing it rendered offline.

## 2. Read what you built

Scroll the output and find these three. Each is one YAML doc, tagged with a `composition-resource-name`
annotation:

- the Namespace — labels for `team: alpha`, `product: demo`, `stage: dev`;
- the ECR Repository — `external-name: team-alpha/demo-web`;
- the IAM Role — `Pod-alpha-demo-dev-web`.

Now count the composed resources:

```console
crossplane render environments/demo-dev.yaml ../charts/environment-api/files/composition.yaml \
  render/functions.yaml --extra-resources render/environmentconfig.yaml | grep -c "composition-resource-name:"
```

You should get **17** — the fixed set plus one service's stack.

## 3. Change the stage — watch the names move

Work on a copy so you never touch the repo:

```console
cp environments/demo-dev.yaml /tmp/my-env.yaml
```

Open `/tmp/my-env.yaml` and change `stage: dev` to `stage: test`. Predict first: which names change? Then
re-render the copy:

```console
crossplane render /tmp/my-env.yaml ../charts/environment-api/files/composition.yaml \
  render/functions.yaml --extra-resources render/environmentconfig.yaml | grep -E "external-name:|kind: Namespace" | head
```

The namespace derives to `alpha-demo-test` and the role to `Pod-alpha-demo-test-web` — but the ECR repo
stays `team-alpha/demo-web`. If you predicted that, you've got it: names are either product + service
(identity, stage-independent) or product + stage (the environment). Identity stays put; the place changes.

## 4. Add a service — watch the footprint grow

In `/tmp/my-env.yaml`, add a second service alongside `web`:

```yaml
  services:
    web: { repoPath: services/web, serviceAccount: demo-web }
    api: {}
```

Re-render and count again:

```console
crossplane render /tmp/my-env.yaml ../charts/environment-api/files/composition.yaml \
  render/functions.yaml --extra-resources render/environmentconfig.yaml | grep -c "composition-resource-name:"
```

Now you get **20**, up from 17 — a delta of **+3**. A new per-service stack appeared for `api`, but only
its ECR trio (`Repository` + `RepositoryPolicy` + `LifecyclePolicy`), because `api: {}` declares no
`serviceAccount`. The IAM role and Pod-Identity association render only when a service declares a
`serviceAccount` (say, `api: { serviceAccount: demo-api }`), which would make it +5 (→ 22) instead of +3.
The gate is the `serviceAccount`, not the image. That's the *fixed set + (per-service resources ×
services)* formula, live in front of you.

## What you did

Offline and safely, you rendered a real environment, read its footprint, watched names derive from the
model's coordinates, and grew the footprint by adding a service. No cluster, nothing to break — and the
output is exactly what the platform would build.

## Next — 🔒 when the learning sandbox is live

These steps need the sandbox, which isn't available yet:

- Apply your claim and watch ArgoCD sync it into a real namespace.
- `crossplane resource trace` it and watch the tree go `Ready`.
- Delete the ECR repo by hand and watch Crossplane recreate it — the self-heal you can only read about
  today.

Until then, keep experimenting with `render`: try an invalid `tier`, add a `quota`, add a third service.

## Go deeper

- [Orientation](orientation.md) — how it all fits together.
- [Deep dive: how the Composition renders](deep-dive-composition-rendering.md) — the go-template behind
  what you just rendered.
- [Reference](reference.md) · the [portal glossary](../glossary.md).
