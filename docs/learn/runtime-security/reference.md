# Learn: Runtime Security — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first. Verified against code +
live (both clusters up). No account IDs, keys, or secret values appear here.

## The defense-in-depth stack

Admission → network-identity → **encryption → cryptographic-identity → behavioral-detection**. The last three
operate *at runtime* — this module. (The first two are [Policy](../policy/orientation.md) +
[Foundations](../foundations/deep-dive-the-cluster.md).)

| Layer | Control | Mechanism | Status |
| --- | --- | --- | --- |
| encryption-in-transit | WireGuard | Cilium transparent encryption (in-kernel WG, pod-to-pod) | **LIVE both clusters** |
| host encryption | node-to-node | `node_encryption` | designed (off) |
| cryptographic identity | mTLS + SPIRE | Cilium mutual auth, embedded SPIRE, per-path `authentication.mode: required` | **LIVE — preprod showcase, 1 pair** |
| fleet/tier mTLS enforcement | per-`regulated`-tier | auth-policies wired into the Environment Composition | **designed, not built** (no regulated tenant) |
| behavioral detection | Falco | eBPF syscall monitoring, per-node DaemonSet | **LIVE both — detecting; routing deferred** |

## Falco — runtime threat detection ([ADR-045](../../adrs/045-falco-runtime-threat-detection.md), Accepted)

- **Idea:** admission (Kyverno) gates *config*; supply-chain (cosign) gates the *image*; Falco watches *runtime
  behavior* — a shell in a container, a read of `/etc/shadow`, a write below a binary dir, priv-esc, an
  unexpected connection. **Detects, does not block** (no Audit→Enforce flip — it always alerts).
- **Mechanism:** taps the **syscall** boundary via **modern eBPF (CO-RE)** (`driver_kind = "modern_ebpf"` —
  no kernel-module build, portable across the AL2023 6.x kernels, coexists with Cilium's eBPF at different
  hooks). A **privileged DaemonSet** (one per node, tolerates *all* taints → cluster-wide) in the `falco`
  namespace. Matches each event against the **default upstream ruleset** (rules-as-code, priority + MITRE
  ATT&CK tags); **no custom rules wired**. `json_output: true` for clean downstream fields.
- **Versions/live:** chart `9.0.0`, Falco `0.44.0`, falcoctl `0.13.0`. DaemonSet 3/3 on the hub, streaming
  real events (e.g. rule `Contact K8S API Server From Container`, priority `Notice`, tag `T1565`).
- **falcosidekick — routing (DEFERRED):** deployed (2 replicas) but **`Enabled Outputs: []`** → logs to
  **stdout only**; nobody is paged. SNS/Slack/observability outputs are a one-var change
  (`falcosidekick_config = { sns = { topicarn = … } }`) tracked by **#116/#102**. The `aws/sns-notifications`
  module names Falco as a *future* publisher; no Falco alert in the observability stack yet.
- **Tuning is the real cost:** the stock ruleset is noisy (it flags the Tailscale operator/Beyla/external-dns
  *legitimately* contacting the K8s API as "unexpected"). Sequence: **detect-to-stdout → observe → tune →
  then wire outputs.** Tuning = add an exception/allowlist macro via a custom-rules ConfigMap (a module
  extension; not wired today).
- **Deployed:** preprod (#116/#134) + platform (2026-07-06, #149).

## East-west zero-trust ([ADR-057](../../adrs/057-service-identity-and-east-west-zero-trust.md))

Two layers on top of the Cilium default-deny NetworkPolicy floor — **Cilium-native, no sidecar mesh** (a mesh
is only justified by L7 east-west traffic management, which isn't needed).

### WireGuard transparent encryption — **LIVE both clusters**

- In-kernel WireGuard encrypts *all* pod-to-pod traffic, transparently, no app change; sits under the overlay
  tunnel (MTU auto-adjusted). Fleet default, not tier-gated. `node_encryption` (host-to-host) stays **off**
  (later, more invasive).
- Module (`infra/modules/cilium/`): `encryption_enabled` (default off), `encryption_type` (`wireguard`|`ipsec`),
  `node_encryption`. Live units set `encryption_enabled = true` on **both** clusters.
- **Gotcha:** `enable-wireguard` is read **only at Cilium agent startup** → a running fleet needs
  `kubectl rollout restart ds/cilium -n kube-system`, else agents log `Mismatch: enable-wireguard actual=false
  expectedValue=true`. Verify: per-node `network.cilium.io/wg-pub-key` + `cilium-dbg status → Encryption:
  Wireguard`.

### mTLS mutual auth (Cilium + embedded SPIRE) — **LIVE preprod showcase (1 pair), not platform**

- Cilium **mutual authentication** with an **embedded SPIRE** (SPIFFE) as the identity source: SPIRE attests
  workloads (k8s PSAT) and issues **SVIDs**; a workload opts into enforcement per-path with a
  `CiliumNetworkPolicy` `authentication.mode: required`; Cilium does a SPIRE-backed handshake before allowing
  the connection (cached in a BPF auth-cache, `cilium-dbg bpf auth list → AUTH TYPE: spire`). **Bytes are
  still WireGuard-encrypted** — mTLS adds *identity*, not encryption.
- Module: `mutual_auth_enabled` (→ `authentication.enabled` + `authentication.mutual.spire.enabled`),
  `spire_install` (embedded vs external), `spire_persistence`, `spire_storage_class`. Live: **preprod only**
  (`mutual_auth_enabled = true`); platform has no `cilium-spire` namespace.
- **Proof (preprod):** the real `alpha-shop → alpha-checkout` call is SPIRE-mutually-authenticated; a
  cross-team **impostor is DROPPED** at checkout's ingress. The auth-required CNP lives in the **alpha-shop app
  repo** (not `gitops/`).
- **Decision resolved:** **embedded** SPIRE (attests via k8s PSAT, clean on the overlay+WireGuard stack);
  standalone SPIRE only if identity is needed beyond Cilium (app-level mTLS, cross-cluster federation).
- **Status:** live *showcase*, one pair, preprod. **Fleet-wide, `regulated`-tier-gated** enforcement (wire
  auth-policies into the Environment Composition per tier) is **designed, not built** — parked until a
  regulated tenant exists.
- **Gotchas:** (1) `authentication.enabled: true` is mandatory (off = *denies* auth-required traffic).
  (2) needs a rolling Cilium restart (startup-read config). (3) cross-namespace needs **both** netpol halves
  (env namespaces default-deny egress too; a k8s `ipBlock` doesn't cover in-cluster identities). (4) the
  delivery AppProject must permit tenant `(Cilium)NetworkPolicy` (#1207). (5) SPIRE's PVC datastore hits the
  **EBS-encryption SCP** → needs an encrypted StorageClass (the preprod encrypted-gp3 default fix #1202/#1203);
  `spire_persistence=false` = ephemeral (fine for a spike, not a showcase).

## Where the runtime hardening also comes from (cross-refs)

- **Kyverno securityContext auto-injection** (`mutate-pod-defaults`): `allowPrivilegeEscalation:false`,
  `capabilities.drop:[ALL]`, `seccompProfile:RuntimeDefault`, `automountServiceAccountToken:false` — **live,
  Enforce** (see [Policy](../policy/orientation.md)).
- **Regulated-tier hardening** (`runAsNonRoot`, `readOnlyRootFilesystem`) — live *for the tier*, unexercised
  (no regulated tenant).

## Gotchas (quick)

- **WireGuard needs a Cilium DS restart** to activate (startup-read).
- **`authentication.enabled` off ⇒ auth-required traffic is *denied***, not bypassed.
- **Falco detects, never blocks** — and today **pages no one** (`Enabled Outputs: []`).
- **Untuned Falco = false-positive firehose** — tune before wiring outputs.
- **mTLS is a preprod one-pair showcase** — not platform, not fleet-wide.

## Go deeper

Deep dives: [Falco](deep-dive-falco.md) · [east-west zero-trust](deep-dive-east-west-zero-trust.md).
Related: [Policy & admission](../policy/orientation.md) · [Supply chain](../supply-chain/orientation.md) ·
[Foundations → the cluster](../foundations/deep-dive-the-cluster.md). External:
[Falco](https://falco.org/docs/) · [Cilium transparent encryption](https://docs.cilium.io/en/stable/security/network/encryption/) ·
[Cilium mutual authentication](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication/) ·
[SPIFFE/SPIRE](https://spiffe.io/docs/latest/spiffe-about/overview/) · [MITRE ATT&CK](https://attack.mitre.org/).
