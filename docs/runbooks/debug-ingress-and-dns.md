# Runbook: Debugging Tenant Ingress, DNS, and TLS

> **Severity:** Medium (app unreachable / degraded ingress)
> **On-call scope:** Development Teams (first pass) / Platform Engineering (Cilium, cert/DNS infra)
> **Related:** [Deploy App to Preprod](deploy-app-preprod.md),
> [Crossplane Tenant API](../architecture/crossplane-tenant-api.md),
> [ADR-061: Tenant Ingress & Custom Domains](../adrs/061-tenant-ingress-and-custom-domain-strategy.md)
>
> **Last reviewed:** 2026-06-08

---

"My app isn't reachable", "TLS fails", or "my hostname is rejected." Work the tree top to bottom — each
layer assumes the ones above it pass. All examples use `team-alpha`, app `demo`, host
`demo-alpha.preprod.aws.refplat.org` (the [generated host](../adrs/060-tenant-app-hostname-convention.md) —
app repos do **not** hardcode it; argocd-apps injects it).

The path a request takes:

```text
client ─DNS─▶ Route53 record (external-dns) ─▶ Gateway NLB ─▶ Cilium Envoy (TLS terminate, cert-manager)
        ─Host match─▶ HTTPRoute (must be Active in restrict-route-hostnames) ─▶ Service ─▶ pods
```

---

## Table of Contents

1. [Quick triage](#quick-triage)
2. [Kyverno rejected the HTTPRoute hostname](#kyverno-rejected-the-httproute-hostname)
3. [HTTPRoute not attaching to the Gateway](#httproute-not-attaching-to-the-gateway)
4. [DNS does not resolve](#dns-does-not-resolve)
5. [TLS error](#tls-error)
6. [Cilium ingress identity / NetworkPolicy](#cilium-ingress-identity--networkpolicy)

---

## Quick triage

```bash
kubectl get httproute demo -n team-alpha                     # is it Accepted by a parent?
dig +short demo-alpha.preprod.aws.refplat.org                # does DNS resolve?
curl -sv https://demo-alpha.preprod.aws.refplat.org 2>&1 | head -30   # TLS + response
```

- **Route rejected at apply / not created** → [Kyverno](#kyverno-rejected-the-httproute-hostname).
- **Route exists but `PARENTS`/status empty** → [attachment](#httproute-not-attaching-to-the-gateway).
- **`dig` returns nothing (NXDOMAIN)** → [DNS](#dns-does-not-resolve).
- **TLS handshake / cert error** → [TLS](#tls-error).
- **Resolves + valid cert but `upstream connect error` / timeout** →
  [Cilium identity](#cilium-ingress-identity--networkpolicy).

---

## Kyverno rejected the HTTPRoute hostname

**Symptom:** ArgoCD sync fails or `kubectl apply` is rejected with a `restrict-route-hostnames-team-alpha`
admission error.

**Diagnosis.** The per-team `restrict-route-hostnames` ClusterPolicy admits a hostname only when **both**
hold (ADR-061 Phase 2a):

1. the host is in the team's allow-list — the **derived generated host** (`demo-alpha.…` + the
   `demo-alpha-pr-*` preview wildcard) **unioned with** `spec.domains` from the `XTenant` claim; and
2. that host's `status.domains` entry is **`Active`**.

```bash
# The claim's declared aliases (generated host is implicit, never declared)
kubectl get xtenant alpha -o jsonpath='{.spec.domains}' | jq .

# The state machine — a host must be Active to be admitted
kubectl get xtenant alpha -o jsonpath='{.status.domains}' | jq .

# What the policy actually permits
kubectl get clusterpolicy restrict-route-hostnames-team-alpha -o yaml | less
```

**Fixes:**

- **Hardcoded host in the app repo.** Don't. The app's `httproute.yaml` carries a placeholder; argocd-apps
  overwrites `spec.hostnames` with the generated host ∪ aliases. Remove the literal and let injection win.
- **Want a vanity host** (`demo.refplat.org`). Add it under `spec.domains` in
  `gitops/tenant-claims/preprod/alpha.yaml` (PR). Tier-1/2 hosts under `*.preprod.aws.refplat.org` go
  `Active` immediately; tier-3 external domains stay `Pending` (Phase 2b deferred) and are **not** admitted.
- **Host shows `Pending`/non-`Active`.** Expected for external domains — see
  [ADR-061](../adrs/061-tenant-ingress-and-custom-domain-strategy.md). For a platform-domain host stuck
  non-`Active`, inspect the `XTenant` status `reason`/`message` and the Composition.

---

## HTTPRoute not attaching to the Gateway

**Symptom:** `kubectl get httproute` shows no parent / `PARENTS` blank; traffic never reaches the service.

```bash
kubectl describe httproute demo -n team-alpha    # look at Status > Parents > conditions
kubectl get gateway -n default                    # the shared Gateway, GatewayClass cilium
kubectl describe gateway -n default <gateway-name>
```

**Causes and fixes:**

- **Wrong `parentRef`.** Must target the shared Gateway by name in its namespace (`default` on preprod) with
  `sectionName: https`. Confirm the name/namespace against `kubectl get gateway -n default`.
- **Hostname outside the listener wildcard.** The `https` listener serves `hostname: *.<domain>` (e.g.
  `*.preprod.aws.refplat.org`). A host not under that wildcard (a tier-3 external domain) cannot attach to
  the shared listener — that is the deferred Phase 2b case, not a misconfig.
- **Namespace not allowed.** Both listeners are `allowedRoutes.namespaces.from: All`, so any namespace may
  attach. If a `RouteNotAllowed` condition appears, the Gateway was customized — escalate to platform.

---

## DNS does not resolve

**Symptom:** HTTPRoute is attached but `dig demo-alpha.preprod.aws.refplat.org` returns NXDOMAIN.

**Diagnosis.** `external-dns` (sourcing from `gateway-httproute`/`service`) writes Route53 records from
HTTPRoute hostnames. Propagation can take a few minutes.

```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=80

# The record's TXT owner ID must match this cluster (external-dns won't touch records it doesn't own)
AWS_PROFILE=preprod aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> --query "ResourceRecordSets[?contains(Name, 'demo-alpha')]"
```

**Causes and fixes:**

- **HTTPRoute not Active/attached.** external-dns only emits records for routes the Gateway accepts — fix
  [attachment](#httproute-not-attaching-to-the-gateway) first.
- **TXT-owner conflict.** external-dns sets `txtOwnerId = <cluster_name>`; a record owned by another cluster
  is left alone. Check for a stale TXT record from a previous cluster.
- **IRSA missing Route53 perms.** external-dns assumes an IRSA role limited to
  `route53:ChangeResourceRecordSets` on the zone + list actions. A `403` in the logs means the role/zone
  binding is wrong — escalate to platform.
- **Force a re-sync:** `kubectl rollout restart deployment -n external-dns external-dns`.

---

## TLS error

**Symptom:** browser/`curl` cert error; the page won't load over HTTPS.

**Diagnosis.** The shared Gateway terminates TLS with a **single wildcard** certificate
(`*.<domain>`) issued by cert-manager via the Let's Encrypt **DNS-01** challenge through the
`ClusterIssuer` (Route53). The Gateway carries the `cert-manager.io/cluster-issuer` annotation and references
`<gateway-name>-tls`.

```bash
kubectl get clusterissuer                                    # ClusterIssuer Ready?
kubectl get certificate -n default                           # the wildcard cert, READY=True
kubectl describe certificate -n default <gateway-name>-tls
kubectl get challenges -A                                    # DNS-01 challenges in progress
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=80
```

**Causes and fixes:**

- **Certificate `Ready: False` / stuck.** The cert-manager IRSA role needs Route53 DNS-01 perms
  (`GetChange`, `ChangeResourceRecordSets`, `ListResourceRecordSets` on the zone). A `403` in the logs is a
  role issue — escalate to platform.
- **Let's Encrypt rate limit.** ~5 certs per domain per week. `describe certificate`/challenge will say so;
  wait it out — do not loop retries.
- **DNS-01 propagation lag.** The challenge TXT record isn't visible yet; cert-manager polls `GetChange`.
  Give it a few minutes.
- **Per-app cert expectation.** There is **no** per-app cert on the shared Gateway — every
  `*.<domain>` host rides the one wildcard. A "missing cert for my host" almost always means the host isn't
  under the wildcard (an external domain) — see [ADR-061](../adrs/061-tenant-ingress-and-custom-domain-strategy.md).

---

## Cilium ingress identity / NetworkPolicy

**Symptom:** DNS resolves, TLS is valid, but `curl` returns `upstream connect error or disconnect/reset
before headers` or times out.

**Diagnosis.** Cilium's Gateway Envoy reaches backends using the reserved **`ingress` identity (8)** — not
`host` — so a plain Kubernetes NetworkPolicy cannot authorize it. Each tenant namespace must carry the
`allow-gateway-envoy` CiliumNetworkPolicy (provisioned by the Tenant Composition, not app manifests).

```bash
kubectl get networkpolicy -n team-alpha          # default-deny-ingress, allow-gateway-ingress, allow-dns-egress
kubectl get ciliumnetworkpolicy -n team-alpha    # allow-gateway-envoy (must be present)
kubectl get endpoints demo -n team-alpha         # backend pods actually Ready?
```

Platform-side drop trace (always start with drops, not flow traces):

```bash
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system "$CILIUM_POD" -- \
  timeout 10 cilium-dbg monitor --type drop --type policy-verdict
# "identity ingress -> <N> action deny" == the allow-gateway-envoy CiliumNetworkPolicy is missing
```

**Causes and fixes:**

- **Missing `allow-gateway-envoy`.** Re-check the `XTenant` is `READY` (the Composition owns the
  CiliumNetworkPolicy); if the policy is absent, reconcile the claim. Escalate to platform if it won't apply.
- **TLS secret not synced to `cilium-secrets`.** The Gateway TLS secret must exist in `cilium-secrets` as
  `<namespace>-<secret-name>` (e.g. `default-<gateway-name>-tls`). `kubectl get secret -n cilium-secrets`.
- **No endpoints.** Empty `endpoints` means the Service selector doesn't match running pods — fix the
  Deployment/Service, see [Deploy App to Preprod](deploy-app-preprod.md#network-debugging).
