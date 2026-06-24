# Spike Plan — Triage Copilot Eval Corpus (ADR-080 gating spike)

**Status:** Proposed (2026-06-24) · gates [ADR-080](../adrs/080-triage-copilot.md) D6

## The one question this spike answers

**Can we manufacture a usable, automatable answer key for the triage copilot by breaking things on
purpose?** The copilot has no deterministic oracle (no lookup from "alert + telemetry" → "correct root
cause"), and we cannot mine one from history (dev telemetry is deleted after ~15 days). If we cannot
produce a graded eval signal, we should not build the agent. This spike de-risks that **before** any
agent runtime is written.

## Decisions locked (from the ADR-080 design thread)

- **Build the corpus forward by fault injection** (fault-injection-first; postmortems + production-shadow come later).
- **Freeze fixtures** — snapshot the telemetry at injection time and replay the snapshot; do **not** keep backends hot.
- **Structured-taxonomy grading** — label and agent output fill the same form, so scoring is set-membership, not judgment.
- **Walled-off preprod** — inject in a dedicated throwaway namespace on the preprod cluster (rides the #590/P10 spoke work).
- **Scripted faults, no chaos framework** — kubectl/helm + k6 + Cilium/ESO toggles (consistent with the Spike-3 "adopt nothing new at tier-0" stance).

## GO / NO-GO

**GO** if the harness produces a graded signal that is:

1. **Automatable** — scored with zero human-in-the-loop judgment.
2. **Stable** — `pass^k` above threshold (the same fixture replayed *k* times yields a stable hypothesis set).
3. **Discriminating** — a known-good prompt clearly outscores a deliberately-degraded prompt on the same fixtures.

**NO-GO** (a cheap, real finding) if: the signal is too noisy to separate good from bad prompts; the frozen
snapshot can't reproduce what the agent needs to reason; or real failure modes can't be expressed as structured
labels. Any of these is a legitimate stop **before** sinking effort into the agent.

## The fault scenarios (~10)

Each maps to a real alert and/or common app failure mode, is scripted, and carries a known structured label.
`svc` = the throwaway test app in the eval namespace.

| # | Scenario | How to inject (scripted) | Trips | Structured label `{service, change, failure_class}` |
|---|---|---|---|---|
| 1 | Bad deploy → crashloop | Roll an image with a broken entrypoint / immediate non-zero exit | KubePodCrashLooping | `{svc, deploy:<sha>, crashloop}` |
| 2 | OOM kill | Tight memory limit + a memory-hog endpoint | OOMKilled / restart | `{svc, config, oom}` |
| 3 | Dependency latency | Point svc at a slow stub (or a latency-injecting sidecar) | p99 latency / SLO burn | `{svc, dependency, latency}` |
| 4 | Bad config | Deploy a wrong/missing env value → 500s on startup | error-rate alert | `{svc, config, config_error}` |
| 5 | Cilium policy-deny | Apply a CiliumNetworkPolicy blocking svc egress | CiliumDropRate (#614) | `{svc, infra, policy_deny}` |
| 6 | Secret failure | Break svc's ExternalSecret (point at a missing key) | ExternalSecretNotReady | `{svc, infra, cert_secret}` |
| 7 | CPU saturation | CPU-hog under tight limits → throttling | latency / throttle | `{svc, resource_saturation}` |
| 8 | DB pool exhaustion | Open more CNPG connections than the pool allows | db errors / saturation | `{svc, dependency:db, saturation}` |
| 9 | Dependency down | Scale a backing dependency to zero | `<dep>` Down alert | `{dep, infra, down}` |
| 10 | **Compound under load** | Scenario 1 or 3 **+ k6 load** for realistic noise | latency + errors | `{svc, deploy, latency}` (noisy) |

Scenario 10 is the deliberate test of the "injected faults are too clean" gap.

## Build checklist (the harness)

- [ ] **A. Test target app** — a tiny, deliberately-mutable service deployed to a throwaway eval namespace on preprod (reuse the demo-app shape; Kyverno-compliant so it can actually deploy).
- [ ] **B. Injection scripts** — one per scenario; idempotent: apply fault → wait for the alert/telemetry to manifest → record start/end timestamps + the structured label.
- [ ] **C. Snapshot capturer** — given `(namespace, window)`, run the **deterministic context-pack** queries (PromQL/Mimir, LogQL/Loki, Tempo, k8s read, recent-deploy/GitHub) and freeze results to a fixture; stash bulky raw telemetry in S3 if needed.
- [ ] **D. Fixture format** — versioned `{id, scenario, alert_group, queries+results snapshot, label, rubric, window}`; small fixtures in-repo, large blobs in S3.
- [ ] **E. Structured schema** — the label + hypothesis JSON schema (the taxonomy above); include an `other/unknown` `failure_class` escape hatch that flags a fixture for taxonomy expansion.
- [ ] **F. Candidate triage prompt** — first-cut prompt: takes a fixture's context-pack, emits ranked structured hypotheses via **Bedrock Claude** (Sonnet 4.6, structured outputs / strict tool use; Pod-Identity auth).
- [ ] **G. Grading function** — compares hypotheses vs label: top-1/top-3 culprit-service, failure-class accuracy, **change-attribution** (strict), `pass^k`. Emits a scorecard.
- [ ] **H. Runner + report** — loop fixtures × *k*, aggregate, print the scorecard; eyeball discrimination + stability.

## Sequence

- **Phase 0 — venue.** Scale up preprod; create the throwaway eval namespace; deploy the test app; confirm the **preprod observability spoke (#590/P10)** captures the app's metrics/logs/traces. *(Hard dependency: this spike needs P10 far enough along that preprod telemetry is queryable.)*
- **Phase 1 — freeze first, no agent.** Build C + D + E. Prove you can take a faithful "photograph" of a window and read it back.
- **Phase 2 — three easy faults.** Build B for scenarios 1, 5, 6 (cleanest) → produce 3 fixtures.
- **Phase 3 — first graded run.** Build F + G; run over the 3 fixtures; confirm you get *a* graded score at all.
- **Phase 4 — full set + discrimination.** Expand to all ~10 (incl. #10 compound-under-load); run *k*× each; compute discrimination (does a deliberately-degraded prompt score worse?) + stability.
- **Phase 5 — GO/NO-GO writeup.** Score against the three criteria; record findings (incl. any NO-GO).

## Out of scope (deferred to the build, post-GO)

The real agent runtime, the bounded-agentic follow-up loop, the human-feedback/online-signal pipeline, the
LLM-judge, multi-cloud model hosting, and the other ADR-080 design threads (storm control, calibrated
uncertainty, surfaces). This spike builds **only** the answer-key machinery.

## Risks & mitigations

- **Snapshot fidelity gap** — a frozen photo lacks something the agent needs. *Mitigation:* snapshot a broad raw window beyond the deterministic context-pack; record exactly what was captured per fixture.
- **Faults too clean** — real incidents are noisy/cascading. *Mitigation:* scenario #10 (compound under load); calibrate difficulty against the few real postmortems later.
- **Taxonomy doesn't fit a real fault** — *Mitigation:* the `other/unknown` escape hatch + a flag to grow the enum; a high `other` rate is itself a finding.
- **Preprod entanglement** — demolition disturbs other staging work. *Mitigation:* a dedicated eval namespace/test-product; faults scoped to it.
- **P10 not ready** — no preprod telemetry to capture. *Mitigation:* Phase 0 gates on it; if P10 slips, the fallback is a small dedicated cluster in the test account (higher build cost — see ADR-080 venue discussion).

## Artifacts

Scripts under `~/spikes/spike-triage-eval/` (mirroring the prior Spike-1/2/3 layout); fixtures in-repo +
S3; a `FINDINGS.md` with the GO/NO-GO verdict and the scorecards.
