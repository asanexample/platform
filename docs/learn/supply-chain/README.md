# Learn: Supply Chain

How the platform knows an image is *trustworthy* — really your code, built by a CI you trust, untampered —
and refuses to run anything that isn't. The *produce* side of the trust story; [Policy & Admission](../policy/)
is the *enforce* side.

**Audience:** platform engineers who own the shared signing pipeline + verify policies. Developers get a real
payoff from the **2-minute view** (the surprise is how little you do). Fluent in cosign + SLSA? The
[Reference](reference.md).

**Before you start:** [Life of a Deployment](../spine/life-of-a-deployment.md) and ideally
[Policy & Admission](../policy/orientation.md). Know what an image *digest* is.

## Read in this order

1. **[Orientation](orientation.md)** — the teaching journey: trust *provenance, not names*; the three facts
   you can read off a **real** signed image with one `cosign` command (keyless signature, SLSA provenance +
   SBOM, the repo trust anchor); the **thin-caller** model (teams inherit security, can't weaken it); and
   verify-at-admission.
2. **[Reference](reference.md)** — the pipeline, the real `cosign` commands, the trust rule, the verify
   policies, and the gotchas (signed ≠ safe; repo-rename breaks trust).

## Then, to go deeper on the real system

- The *enforce* half: [Policy & Admission](../policy/orientation.md); the whole flow:
  [The Life of a Deployment](../spine/life-of-a-deployment.md); the threat framing:
  [The Security Model](../spine/the-security-model.md).
- Onboard your app (the thin-caller snippet): the `supply-chain-onboarding` skill.
- Why it's shaped this way: [ADR-042](../../adrs/042-isolated-build-provenance-slsa-l3.md) (isolated SLSA L3
  provenance), [ADR-050](../../adrs/050-shared-build-sign-reusable-workflow.md) (shared build-sign),
  [ADR-036](../../adrs/036-github-actions-oidc-federation.md) (GitHub OIDC).
