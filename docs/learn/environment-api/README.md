# Learn: the Environment API

How environments get provisioned on this platform — the Crossplane machine that turns one short YAML
claim into a whole running footprint (namespace, image registry, AWS permissions, guardrails).

**Audience:** platform engineers. Developers only need the 2-minute view at the end of the orientation.
Already fluent in Crossplane? Skip straight to the [Reference](reference.md) — it's the terse lookup for
readers who already hold the model.

**Before you start:** you should know what a container is and that Kubernetes has YAML-described
resources it makes real. That's the whole floor.

## Read in this order

1. **[Orientation](orientation.md)** — the teaching journey. Start here. Watch the real `alpha-shop-dev`
   environment get built end to end, and leave able to explain how it works.
2. **[Reference](reference.md)** — look-up: the full claim spec, everything the Composition provisions,
   a glossary, the gotchas that bite, and curated links for learning Crossplane itself.
3. **[Cheatsheet](cheatsheet.md)** — the run-verified commands to inspect, debug, and verify an
   environment (`kubectl` / `crossplane` / `aws`), with access notes.

## Try it hands-on

- **[Tutorial: render your first environment](tutorial-render-an-environment.md)** — a guided, **offline**
  walkthrough: render a real environment, read its footprint, change it, watch the output move. No cluster,
  no access. *(Provisional — the live-provisioning steps light up when the learning sandbox ships.)*

## Deep dives

Teaching-voiced depth on one hard mechanism, once you have the model:

- **[How the Composition renders](deep-dive-composition-rendering.md)** — open the "recipe": the
  three-function pipeline, the go-template, and how one claim + the cluster's constants become the whole
  footprint. For operating or extending the Composition.

## Then, to go deeper on the real system

- Architecture (as-built): [Crossplane Environment API](../../architecture/crossplane-environment-api.md)
- Onboard/operate an environment: the `environment-onboarding` skill +
  [runbook](../../runbooks/environment-onboarding.md)
- Change the machine itself: the `crossplane-composition-authoring` skill
- Why it's shaped this way: [ADR-067](../../adrs/067-idp-domain-model.md) (domain model),
  [ADR-048](../../adrs/048-federated-per-cluster-crossplane.md) (federated per cluster)
