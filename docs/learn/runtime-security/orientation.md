# Learn: Runtime Security — orientation

How the platform defends a workload *while it runs* — after the admission gate has already let it in. The
other security modules stop bad things at the door. This one **assumes something gets through anyway** and
protects the running workload: encrypt every conversation, make each service prove its identity, and watch for
misbehavior.

This is for platform engineers, and for anyone who's asked "we have admission policy and signed images — what
else is there?" [Policy & admission](../policy/orientation.md) (the door — Kyverno) and
[Supply chain](../supply-chain/orientation.md) (the ID check — signed images) are the gates this module
complements; [Foundations → the cluster](../foundations/deep-dive-the-cluster.md) explains Cilium, which does
the heavy lifting here. Know roughly what a container and a syscall are, and we'll build the rest.

## The question

The platform already blocks a lot. Kyverno rejects a non-compliant pod at `kubectl apply`; cosign refuses an
unsigned image. Both are point-in-time gates — they check the config and the image, then step aside. But a pod
that passed both can still be exploited at runtime, ship a compromised dependency, or be hijacked — and then
spawn a shell, read `/etc/shadow`, or open a connection it never should. Even a perfectly-behaved pod is
talking to other pods over a network you'd rather an attacker couldn't read or impersonate.

So: once a workload is *running* — past every admission gate — how do you keep its traffic private, stop an
impostor from talking to it, and notice when it does something it shouldn't?

## Assume something got in

Runtime security is the assume-breach layer. The admission gates decide what's allowed to run; runtime
security accepts that a gate will eventually be wrong and defends the workload as it runs. Three moves:
**encrypt** every pod-to-pod conversation so the wire is private, **authenticate** each service
cryptographically so an impostor is dropped even inside the cluster, and **detect** anomalous behavior at the
kernel so a hijacked container gets caught in the act. These are the last layers of defense-in-depth, the ones
that operate at runtime rather than at the door.

The platform's security is layered, and each module owns a layer:

1. **Admission** ([Policy](../policy/orientation.md)) — Kyverno gates the *config* at deploy time.
2. **Supply chain** ([Supply chain](../supply-chain/orientation.md)) — cosign/SLSA gates the *image*.
3. **Network identity** ([Foundations](../foundations/deep-dive-the-cluster.md)) — Cilium default-deny decides
   *who may talk to whom*.
4. **Encryption in transit** — WireGuard makes the traffic *ciphertext*. ⟵ this module
5. **Cryptographic identity** — mTLS makes a service *prove who it is*. ⟵ this module
6. **Behavioral detection** — Falco watches *what a container actually does*. ⟵ this module

The first three are gates and rules, covered elsewhere. The last three are runtime security — the subject
here.

Think of a secure building, past the front door. The lock and the ID check at the entrance (admission plus
signed images) decide who gets in, but a careful building doesn't stop there, because someone will eventually
tailgate through. Inside, every internal message travels in a **sealed pneumatic tube** (WireGuard — a tap on
the pipe sees only ciphertext); each room checks a **cryptographic badge** before admitting you (mTLS — a
stranger in the right-colored shirt is still turned away); and **motion sensors** watch every room for someone
doing something they shouldn't (Falco). Where it breaks: the sealed tube doesn't check *who* sent the capsule
(encryption isn't identity), and the motion sensor only alerts — it doesn't stop the intruder (Falco detects,
it doesn't block). That's why you need all three.

The tour follows the stack: the two east-west moves — encrypt, then authenticate — then behavioral detection.

---

## Stop 1 — encrypt the wire: WireGuard (live, fleet-wide)

Start with the cheapest, broadest win. Cilium NetworkPolicy already decides who may talk to whom, but the
traffic itself — pod-to-pod across the nodes — is plaintext on the wire. Cilium transparent encryption with the
WireGuard backend fixes that: in-kernel
WireGuard encrypts all pod-to-pod traffic, transparently, with **no app change**. It slots under the existing
overlay tunnel and makes the bytes ciphertext.

> *Sealed pneumatic tubes.* Every capsule between rooms is opaque; a tap on the pipe reads nothing. It doesn't
> check the sender — it just makes the channel private.

This is live on both clusters — every node carries a WireGuard public key and `enable-wireguard: true`. It's a
fleet default, not tier-gated, because encryption-in-transit is a blanket good. The one gotcha: enabling it
flips a config value that Cilium reads **only at agent startup**, so a running fleet needs a
`kubectl rollout restart ds/cilium` to actually bring the tunnels up — otherwise agents log
`Mismatch: enable-wireguard actual=false expectedValue=true`.

---

## Stop 2 — prove identity: mTLS with Cilium + SPIRE (a preprod showcase)

Encryption makes the wire private, but it doesn't answer *who is this, really?* A network policy admits a pod
by its label, and an impostor pod in another namespace could wear the right label. Zero-trust wants a
cryptographic identity: a service that *proves* who it is with an attestable credential, so a fake is dropped
at the handshake.

The platform does this Cilium-native, with no sidecar mesh — Cilium **mutual authentication** backed by an
**embedded SPIRE** (the SPIFFE identity system). SPIRE attests each workload and issues it a signed identity
(an SVID); a workload opts into enforcement per-path with a `CiliumNetworkPolicy` carrying
`authentication.mode: required`, and Cilium does a SPIRE-backed identity handshake before allowing the
connection. The data bytes are still WireGuard-encrypted — mTLS adds the identity check, it doesn't replace the
encryption.

> *Showing your ID badge to enter each room.* Even inside the building, the receiving room checks a
> cryptographically-attested badge. A stranger who tailgated in — even in the right-colored shirt — is turned
> away at the door.

The honest status: this is built and live, but as a **showcase on preprod only**, one service pair. The real
`storefront → checkout` call is SPIRE-mutually-authenticated, and a cross-team impostor is **dropped** at
checkout's door (proven live). But it's **not on the platform cluster**, and fleet-wide, tier-gated
enforcement — wiring auth-required policies into the Environment provisioner *per compliance tier*, gated on
`regulated` — is **designed, not built**, deliberately parked until a regulated tenant actually exists (none
does today). So: encryption everywhere, identity proven but narrow. The
[east-west deep dive](deep-dive-east-west-zero-trust.md) has the mechanism and the gotchas.

---

## Stop 3 — watch behavior: Falco (live, detecting… quietly)

Encryption and identity protect the network. But what about the workload's own behavior — a hijacked container
spawning a shell, reading a secret file, escalating privileges? No manifest can describe "don't do that," so
admission is blind to it. Falco is the answer: it
taps the kernel syscall boundary (via modern eBPF) from a privileged DaemonSet on every node, and matches each
syscall against a rules-as-code ruleset — alerting on a shell in a container, a read of `/etc/shadow`, an
unexpected outbound connection, a privilege escalation, each tagged with its MITRE ATT&CK technique.

> *The motion sensors inside the house.* Kyverno is the lock on the door — it decides what gets in. Falco is
> the motion sensor — it watches what happens, and, crucially, it **detects, it doesn't block**: it alerts a
> human, it doesn't stop the syscall.

The honest status: Falco sees everything on both clusters right now — and tells no one yet. The DaemonSet is
live and streaming real events, but the alert-routing layer (falcosidekick) has **no outputs wired** — its
`Enabled Outputs: []` means detections go to stdout only; nobody is paged. Routing to Slack/SNS/the
observability stack is a deferred next step. This is deliberate sequencing: the stock ruleset is noisy — it
flags the Tailscale operator, Beyla, and external-dns *legitimately* contacting the K8s API as "unexpected" —
so you run to stdout first, watch what fires, and tune before wiring it to a pager. Untuned alerts on a
firehose of false positives are worse than no alerts. The [Falco deep dive](deep-dive-falco.md) covers the
mechanism, the tuning burden, and the deferred routing.

---

## The honest status — what's live vs designed

Runtime security is the most partial of the security modules, and saying so is the point.

- **Live, fleet-wide:** WireGuard east-west encryption (both clusters); Falco detection (both clusters,
  DaemonSet streaming). Plus the admission-hardening that feeds runtime posture — Kyverno auto-injecting
  `securityContext` defaults (see [Policy](../policy/orientation.md)).
- **Live but narrow or muted:** mTLS identity (a preprod one-pair showcase, not platform, not fleet-wide);
  Falco alert routing (built but outputs empty — detects, doesn't page).
- **Designed, not built:** tier-gated fleet-wide mTLS enforcement (parked on "no regulated tenant yet");
  node-to-node (host) encryption; per-cluster Falco rule tuning plus the falcosidekick → SNS/observability
  wiring.

The shape to hold: the encryption layer is genuinely done, the identity layer is real but a showcase, and the
detection layer is live but not yet talking. Assume-breach defense-in-depth, honestly half-built.

## When it breaks — the ones you'll actually hit

- **"I enabled WireGuard but traffic isn't encrypted."** Cilium reads `enable-wireguard` only at startup —
  `kubectl rollout restart ds/cilium -n kube-system`, then verify per-node (`wg-pub-key` plus
  `cilium-dbg status → Encryption: Wireguard`).
- **"My auth-required policy is dropping legit traffic."** `authentication.enabled` must be on globally (off
  means it *denies* auth-required traffic), the Cilium agents need a restart, and cross-namespace calls need
  both netpol halves (egress plus the auth-required ingress).
- **"Falco is screaming about normal pods."** That's the untuned stock ruleset (e.g. "Contact K8S API Server
  From Container" on legit operators). Tune or allowlist the known-good pattern before wiring outputs — and
  note nothing is paged yet regardless (`Enabled Outputs: []`).
- **"Falco caught something — did it stop it?"** No. Falco detects, never blocks. Enforcement and response are
  a human, or a future automation, acting on the alert.

## Go deeper

- [Falco — runtime threat detection](deep-dive-falco.md) — syscalls → eBPF → the DaemonSet → rules, the
  Kyverno-vs-Falco complement, falcosidekick and the deferred routing, and the tuning burden.
- [East-west zero-trust](deep-dive-east-west-zero-trust.md) — WireGuard transparent encryption and the
  Cilium + embedded-SPIRE mTLS showcase, the mechanism, the gotchas, and the honest status.
- The lookup: the [Reference](reference.md). Related: [Policy & admission](../policy/orientation.md),
  [Supply chain](../supply-chain/orientation.md), [Foundations → the cluster](../foundations/deep-dive-the-cluster.md).
