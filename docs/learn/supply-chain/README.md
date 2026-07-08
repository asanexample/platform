# Learn: Supply Chain

How the platform knows an image is trustworthy — really your code, built by a CI you trust, untampered —
and refuses to run anything that isn't. This is the *produce* side of the trust story;
[Policy & Admission](../policy/) is the *enforce* side.

**Audience:** platform engineers who own the shared signing pipeline and verify policies. Developers get a
real payoff here too, and the surprise is how little they have to do. If you already know cosign and SLSA,
skip to the [Reference](reference.md).

**Before you start:** read [Life of a Deployment](../spine/life-of-a-deployment.md), and ideally
[Policy & Admission](../policy/orientation.md). Know what an image *digest* is.

## Read in this order

1. **[Orientation](orientation.md)** — trust provenance, not names. The three facts you can read off a real
   signed image with one `cosign` command (keyless signature, SLSA provenance plus SBOM, the repo trust
   anchor); the thin-caller model, where teams inherit security and can't weaken it; and verify-at-admission.
2. **[Reference](reference.md)** — the pipeline, the real `cosign` commands, the trust rule, the verify
   policies, and the gotchas (signed isn't the same as safe; a repo rename breaks trust).

## Then, to go deeper on the real system

- The *enforce* half: [Policy & Admission](../policy/orientation.md). The whole flow:
  [The Life of a Deployment](../spine/life-of-a-deployment.md). The threat framing:
  [The Security Model](../spine/the-security-model.md).
- Onboard your app (the thin-caller snippet): the `supply-chain-onboarding` skill.
- Why it's shaped this way: [ADR-042](../../adrs/042-isolated-build-provenance-slsa-l3.md) (isolated SLSA L3
  provenance), [ADR-050](../../adrs/050-shared-build-sign-reusable-workflow.md) (shared build-sign),
  [ADR-036](../../adrs/036-github-actions-oidc-federation.md) (GitHub OIDC).
