# Runbook — Supply-Chain Incidents

Incident response for the **image signing & verification** path: pods denied at admission, Sigstore
(Fulcio/Rekor) outages, signing-identity / org changes, and emergency break-glass.

**Scope:** this covers the *supply-chain* policies (`verify-images-*`, `verify-attestations-*`). For the
Kyverno **engine** itself failing (webhook down, admission blocked cluster-wide), see
[`kyverno-break-glass.md`](kyverno-break-glass.md) first — that's the bigger hammer.

Background: [`../architecture/supply-chain-overview.md`](../architecture/supply-chain-overview.md) ·
[`../architecture/cosign-image-signing.md`](../architecture/cosign-image-signing.md) ·
[ADR-042](../adrs/042-isolated-build-provenance-slsa-l3.md).

Key knobs (in the `policy` unit values, applied per cluster):

| Knob | Effect |
|------|--------|
| `enableImageVerification` | master switch for `verify-images-*` |
| `enableAttestationVerification` | master switch for `verify-attestations-*` |
| `verifyFailureAction` / `attestFailureAction` | `Audit` (log only) vs `Enforce` (reject) — **independent** for signatures vs attestations |
| `verifyFailurePolicy` / `attestFailurePolicy` | webhook `Fail` (closed) vs `Ignore` (open) when Kyverno can't evaluate |

---

## 1. A pod is denied at admission

**Symptom:** a Deployment in `<team>-<product>-<stage>` won't roll out; ReplicaSet events show a Kyverno
denial naming `verify-images-product-<team>-<product>` or `verify-attestations-product-<team>-<product>`.

```bash
kubectl --context <cluster> -n <team>-<product>-<stage> describe rs <rs>      # see the admission error
kubectl --context <cluster> get clusterpolicy verify-images-product-<team>-<product> -o yaml | grep -iE "action|failurePolicy"
```

Walk the chain (stop at the first failure):

1. **Is the image signed at all, by the right identity?**

   ```bash
   cosign verify "$IMAGE@$DIGEST" \
     --certificate-identity-regexp "^https://github.com/asanexample/trusted-ci/.github/workflows/build-sign.yml@" \
     --certificate-github-workflow-repository asanexample/app-<team>-<product> \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   ```

   The cert **subject** is the shared `build-sign.yml` reusable workflow (signing is no longer per-app);
   per-product isolation is the `githubWorkflowRepository` extension (= the caller app repo). Policy also
   admits an app-signed fallback for bespoke apps.

   - *No signature* → the app's thin CI didn't call the shared `build-sign` workflow (or signed the
     **tag**, not the digest). Fix the workflow ([onboarding runbook](app-supply-chain-onboarding.md))
     and rebuild.
   - *Signed by a different identity* → wrong caller repo (the `githubWorkflowRepository` extension), or
     the product's `verifySubjects` (derived from the `XEnvironment` claim's `spec.services.<svc>.repo`)
     don't list this repo. Fix the claim + re-apply the `policy` unit.

2. **Are the attestations present + the right predicate types?**

   ```bash
   cosign verify-attestation "$IMAGE@$DIGEST" --type cyclonedx      --certificate-identity-regexp "^https://github.com/asanexample/trusted-ci/.github/workflows/build-sign.yml@"      --certificate-oidc-issuer ...
   cosign verify-attestation "$IMAGE@$DIGEST" --type slsaprovenance  --certificate-identity-regexp "^https://github.com/asanexample/trusted-ci/.github/workflows/slsa-provenance.yml@" --certificate-oidc-issuer ...
   ```

   The SBOM is now produced + signed by the shared `build-sign.yml` reusable workflow; the SLSA
   provenance by the separate `slsa-provenance.yml` — both under `trusted-ci`.

   - *Missing SBOM* → Syft/attest step in the shared `build-sign` workflow failed or used the wrong `--type`.
   - *Missing/forged provenance* → the `slsa-provenance` job didn't run, or the build job **self-attested**
     provenance (two identities → `verifiedCount: 0`). Remove the self-attest; rely only on `trusted-ci`.
   - *cosign v3 used* → new bundle format ≠ Kyverno's default attestor → pin **v2.5.2**.

3. **Can Kyverno reach Sigstore?** Verification fetches the Fulcio cert chain + does a **Rekor** lookup. If
   the cluster can't reach `rekor.sigstore.dev` / `fulcio.sigstore.dev`, every verify times out
   (`webhookTimeoutSeconds: 30`). → go to §2.

**Unblock fast (single product, low risk):** flip *attestations* (or *signatures*) to Audit for that rollout,
fix forward, then re-Enforce. Prefer narrowing to the failing policy over disabling globally.

---

## 2. Sigstore (Fulcio / Rekor) outage

**Symptom:** *many* teams' pods suddenly denied (or admission slow), `cosign verify*` from a workstation
also hangs/fails, Kyverno webhook latency spikes. The images are fine — verification can't reach the
public-good transparency log / CA.

Confirm:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://rekor.sigstore.dev/api/v1/log
curl -sS -o /dev/null -w "%{http_code}\n" https://fulcio.sigstore.dev
# from a cluster pod (egress path Kyverno uses), not just your laptop
```

Check the [Sigstore status page](https://status.sigstore.dev/).

**Response (degrade gracefully, fail open temporarily):**

1. Flip the verification policies to **Audit** (or set `*FailurePolicy: Ignore`) on the affected cluster so
   admission stops blocking on the unreachable log — via the `policy` unit values + apply, or for true
   emergency the [break-glass](kyverno-break-glass.md) webhook edit.
2. Communicate: signatures are still being *produced* in CI; we're only pausing *enforcement*.
3. When Sigstore recovers, **re-Enforce** and confirm a known-good image is admitted again.

> Note: new **signing** in CI also depends on Sigstore (Fulcio issues the cert). During an outage, app
> builds that sign/attest will fail too — that's expected; retries succeed once it recovers.

---

## 3. Signing-identity / org rename

If the GitHub **org** or a repo/workflow path changes, the OIDC `subject` on new signatures changes, and the
existing `verifySubjects` won't match — new images get denied while old ones still verify.

This is a **dual-subject transition** (worked example in
[`cosign-image-signing.md`](../architecture/cosign-image-signing.md) §"Org migration"):

1. **Before** the cutover, add the **new** identity to the team's `verifySubjects` (and
   `trustedCiSubjectRegExp` / `attestCallerRepos` if the trusted-ci repo moved) **alongside** the old one —
   the policy lists alternatives (`count: 1` matches any). Apply the `policy` unit.
2. Cut over CI to the new identity; new images now match the new entry, old images still match the old.
3. After all running images are rebuilt under the new identity, **remove** the old entry and re-apply.

No keys to rotate — identities are short-lived Fulcio certs. "Rotation" here means updating *which OIDC
identities the policy trusts*, always edited in the `XEnvironment` claim (`spec.services.<svc>.repo`) →
`policy` unit (never hand-edited on-cluster).

---

## 4. Suspected compromise of a signing identity

If a product's GitHub repo / OIDC is believed compromised (an attacker could mint valid signatures as that
product):

1. **Revoke trust immediately** — remove that product's entry from `verifySubjects` (and any caller repo from
   `attestCallerRepos`) and apply the `policy` unit. New pods using images "signed by" that identity are now
   denied everywhere.
2. **Quarantine running workloads** — scale down / cordon the product's environment namespaces as warranted.
3. **Audit Rekor** — every signature is in the public transparency log; enumerate what was signed under the
   identity and when:

   ```bash
   rekor-cli search --email <workflow-identity>            # or by image digest
   ```

4. Rotate the GitHub repo/OIDC trust on the AWS side (the
   `github-actions-ecr-push-product-<team>-<product>` role's trust policy — see
   [ADR-036](../adrs/036-github-actions-oidc-federation.md)) and re-onboard with a clean identity (§3
   dual-subject, but the old identity is *removed*, not retired gracefully).

You **cannot** delete a Rekor entry (append-only by design) — that's the point: the tamper-evident record of
what was signed survives the incident for forensics.

---

## 5. Break-glass — ship now, fix later

Genuine emergency (must deploy an unsigned/foreign image, e.g. a vendor hotfix, and the proper path can't be
walked in time). Prefer the **smallest** scope:

| Scope | Action | Reverts to |
|-------|--------|-----------|
| One product, attestations only | set `attestFailureAction: Audit` for that policy / product | re-apply Enforce |
| One product, signatures too | `verifyFailureAction: Audit` | re-apply Enforce |
| Whole cluster, verification | `enableImageVerification: false` (and/or `enableAttestationVerification: false`), apply | re-enable + apply |
| Webhook down / can't apply | delete/patch the Kyverno webhook config — [`kyverno-break-glass.md`](kyverno-break-glass.md) | restore webhook |

**Always:** record *why* and *what* in the incident channel, open a tracking issue, and **re-enable Enforce
the same day**. Audit mode still *logs* policy violations — review `PolicyReport`s for what slipped through
while open:

```bash
kubectl --context <cluster> get policyreport -A | grep -iE "verify-(images|attestations)"
```

---

## Related

- [`../architecture/supply-chain-overview.md`](../architecture/supply-chain-overview.md) — how it all fits + SLSA matrix
- [`../architecture/cosign-image-signing.md`](../architecture/cosign-image-signing.md) — keyless mechanics, org-migration worked example
- [`app-supply-chain-onboarding.md`](app-supply-chain-onboarding.md) — the app CI side
- [`kyverno-break-glass.md`](kyverno-break-glass.md) — engine-level break-glass
- [`../architecture/kyverno-policy-catalog.md`](../architecture/kyverno-policy-catalog.md) — per-cluster enforcement status
