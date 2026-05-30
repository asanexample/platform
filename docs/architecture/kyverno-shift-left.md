# Kyverno Shift-Left (Phase 4) — fail policy violations in app PR CI

Kyverno admission is the **enforcement** point: non-compliant tenant workloads are rejected when they're
applied to the cluster (see [ADR-014](../adrs/014-kyverno-as-policy-engine.md) and
[the policy catalog](kyverno-policy-catalog.md)). The problem with enforcement-only is *timing*: an app
team learns their manifest is non-compliant at **deploy** time (ArgoCD sync fails), long after the PR
merged. **Shift-left** moves the *same checks* into the app repo's **pull-request CI**, so the PR goes
red before merge — fast feedback, same rules.

It is a **feedback** gate, not a new enforcement gate. Admission stays the source of truth; this just
surfaces the verdict earlier.

---

## How it works

A reusable composite action in the platform repo,
[`.github/actions/kyverno-validate`](../../.github/actions/kyverno-validate/action.yml), does cluster-free
what admission does in-cluster:

1. **Render** the platform tenant policies for the team — `helm template` the same `policies-chart` the
   cluster runs, with `mutate` ON (so the auto-injected `securityContext`/labels are present, matching
   the cluster), `verifyImages` OFF (the image isn't built/signed at PR time), and `cleanup` OFF
   (runtime GC, not an admission check). The team's allowed route hostnames come from `teams.hcl` (via
   `hcl2json`), the single source of truth.
2. **Render the app manifests** — `kubectl kustomize <manifests-path>`.
3. **Apply** — `kyverno apply <policies> --resource <manifests> --values-file <ns-labels>`, telling the
   CLI the `team-<team>` namespace carries the tenant label so the tenant-scoped policies match.
4. **Fail** the build if the parsed summary reports any `fail` or `error`.

No cluster, no AWS credentials, no secrets — so it is safe to run on `pull_request`, including from forks.

## Using it in an app repo

Add a `validate.yml` to the app repo (`<org>/app-<team>`). It calls the platform action by ref; nothing
else is needed.

```yaml
# .github/workflows/validate.yml
name: Validate manifests
on:
  pull_request:
jobs:
  kyverno:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Kyverno shift-left validation
        uses: asanexample/platform/.github/actions/kyverno-validate@main
        with:
          team: alpha                 # this app's team
          manifests-path: k8s/preprod # the kustomize dir to check
          # env: preprod              # (default) which teams.hcl supplies allowed hostnames
```

Cross-repo private action use requires the org setting **Settings → Actions → General → Access →
"Accessible from repositories owned by asanexample"** on the platform repo (already enabled).
`@main` is intentional — app PRs validate against the *current* platform policy, so a policy change
surfaces across all apps immediately.

## What it catches (and what it doesn't)

**Catches** (same as admission): wrong/cross-team image registry, mutable/`:latest` tag, missing
resource requests/limits, missing liveness/readiness probes, `LoadBalancer`/`NodePort` services, and
route hostnames outside the team's `teams.hcl` allow-list.

**Does not** (by design — these need the cluster or the built image):

- **Image signature verification** (`verifyImages`) — the image isn't built or cosign-signed at PR time.
  Admission still enforces it. See [cosign-image-signing.md](cosign-image-signing.md).
- **PR-preview hostname rewrites** — preview `HTTPRoute` transforms happen via Kustomize patches in the
  ApplicationSet, validated at admission, not here.
- Anything depending on **live cluster state** (the namespace tenant label is *simulated* via a values
  file).

So a green shift-left check means "this will pass the validate policies"; admission remains the
authority (and is the only thing that enforces signatures).

## Dogfood

The platform CI job **`Kyverno Shift-Left (dogfood)`** (in `.github/workflows/ci.yml`) runs the action
against two committed sample apps in `infra/modules/policy/.kyverno-tests/sample-app/`:

- `compliant/` — must **pass** (and the run asserts `teams.hcl` hostname extraction resolved).
- `broken/` — must **fail** (it trips 7 distinct policies: registry, `:latest`, probes, limits,
  `LoadBalancer`, cross-team image, hostname-squat).

This proves the action end-to-end without needing the app repos, and guards against policy/template
drift breaking the gate.

## Notes / limitations

- **Advisory, not byte-identical to admission.** `verifyImages` is skipped and the namespace label is
  simulated; treat a pass as "validate-clean", not "admission-proven".
- **Kustomize-only render parity.** Apps that template with Helm would need a Helm render step; the
  current action assumes a kustomize dir.
- **`kyverno apply` exit semantics.** The CLI exits non-zero on a validate failure, so the action keys
  off the parsed `fail:`/`error:` counts rather than the raw exit code.
- **Tool pins.** Kyverno CLI is pinned to the cluster chart's appVersion (`1.18.1`); bump both together.
