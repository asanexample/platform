# Runbook: Kyverno Break-Glass & Audit→Enforce Flip

> **Roles:** PlatformAdmin (operate), PlatformDeployer (apply)
> **Related ADR:** [014-kyverno-as-policy-engine](../adrs/014-kyverno-as-policy-engine.md), [040-platform-engineer-access-model](../adrs/040-platform-engineer-access-model.md)
> **Module:** `infra/modules/policy` · **Units:** `infra/live/aws/{preprod,platform}/us-east-1/platform/policy`
>
> **Last reviewed:** 2026-06-28
>
> **Current state:** both clusters run Kyverno in **Enforce** (the replica-floor flip landed in #934); §2 below describes the Audit→Enforce promotion for reference and rollback.

---

## When to use this

Kyverno's admission webhook sits in the pod-creation path. In `Enforce` mode with `failurePolicy:
Fail`, a misbehaving or overloaded webhook — or an over-broad policy — can block legitimate
admissions cluster-wide. This runbook covers (1) emergency disable and (2) the deliberate
Audit→Enforce promotion.

> Authorship of ClusterPolicies is GitOps/PlatformDeployer-only. PlatformAdmin can operate Kyverno
> (scale, patch webhooks for break-glass) but should not author policies (ADR-040).

## 1. Break-glass — stop Kyverno from blocking admission

**Fastest (fail-open the webhooks)** — keeps reporting alive, stops blocking:

```bash
# Make every Kyverno webhook fail-open so admission proceeds even if a policy/engine misbehaves.
kubectl patch validatingwebhookconfigurations kyverno-resource-validating-webhook-cfg \
  --type=json -p='[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'
# Repeat for kyverno-policy-validating-webhook-cfg / mutating webhook cfgs as needed:
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep kyverno
```

**Bigger hammer (delete the webhook configs)** — Kyverno recreates them on its next reconcile/restart:

```bash
kubectl delete validatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno
kubectl delete mutatingwebhookconfigurations  -l webhook.kyverno.io/managed-by=kyverno
```

> Do **not** simply `scale --replicas=0` the admission controller while `failurePolicy: Fail` — that
> makes the webhook unreachable and blocks **all** matching admissions. Fail-open or delete the
> webhook config first.

**Proper fix:** revert the offending policy in Git and re-apply, or flip the unit back to `Audit`
(below). Then let Kyverno restore its webhooks.

## 2. Audit → Enforce flip (and back)

Policies deploy in `Audit` first (records `PolicyReport`s, webhook fail-open). Promote only after
reports are clean against real workloads.

```bash
# 1. Observe in Audit (preprod first):
kubectl get clusterpolicy
kubectl get policyreport -A            # cluster: kubectl get clusterpolicyreport
kubectl get events -A --field-selector reason=PolicyViolation

# 2. When clean, flip the unit input and apply:
#    infra/live/aws/preprod/us-east-1/platform/policy/terragrunt.hcl
#      validation_failure_action = "Audit"  ->  "Enforce"
cd infra/live/aws/preprod/us-east-1/platform/policy && terragrunt apply

# 3. Verify enforcement, then promote the same change to the platform unit.
```

Rolling back is the reverse: set `validation_failure_action = "Enforce" -> "Audit"` and apply
(Terraform also resets the webhook `failurePolicy` to `Ignore`).

## 3. Health checks

```bash
kubectl -n kyverno get pods                       # admission/background/reports/cleanup controllers
kubectl -n kyverno logs deploy/kyverno-admission-controller --tail=100
kubectl get clusterpolicy -o wide                 # READY column should be true
```

## Notes

- System/infra namespaces (`kube-system`, `argocd`, `tailscale`, …) are excluded from environment
  policies; cluster-scoped policies skip platform controllers via the `exclude_principals` list. If a
  platform addon install is blocked, that allow-list (module `exclude_principals`) is the place to fix
  it — verify in `Audit` before re-flipping to `Enforce`.
- Kyverno self-manages its webhook CA (1-year, auto-rotated); no cert-manager dependency.
- **Image verification (Phase 3)** depends on cluster egress to **sigstore** (Fulcio/Rekor) and on the
  Kyverno ECR-read role, bound via **EKS Pod Identity** (ADR-047). A sigstore outage under Enforce blocks admission of *new* images —
  break-glass by setting `verify_failure_action = "Audit"` on the `policy` unit and applying (or
  fail-open the verify webhook as above). The verify policies roll Audit→Enforce independently of the
  other policies via `verify_failure_action`.
- **Attestation verification** (SBOM + SLSA provenance, `verify-attestations-product-<team>-<product>`) has its own
  **separate** knob, `attest_failure_action`, independent of both `validation_failure_action`
  and `verify_failure_action` — so the SBOM/provenance requirement (incl. the trusted-ci L3 provenance,
  ADR-042) can be flipped to `Audit` for break-glass without weakening the image-signature gate.
