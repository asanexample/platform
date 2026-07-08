# Learn: Runtime Security — Falco (deep dive)

> Assumes the [runtime-security orientation](orientation.md) — Stop 3, "watch behavior." There, Falco was the
> *motion sensor inside the house*: the door locks and the ID check (admission + signed images) decide who gets
> *in*; Falco watches what *happens* once they're inside, and **detects — it doesn't block**. This dive opens up
> that one sensor: how a syscall becomes an alert, why it's a privileged per-node DaemonSet, what the live stream
> actually says right now, and why the alarm is wired to *no one* on purpose. Already fluent in eBPF + Falco? →
> the [reference](reference.md) is the terse lookup.

## Why the door and the ID check can't see this

Walk the platform's security layers as gates in time. [Kyverno admission](../policy/orientation.md) runs **once**,
at `kubectl apply`: it inspects the pod's *config* — image registry, probes, `securityContext`, hostPath mounts —
rejects it or lets it in, and **steps aside**. [Supply chain](../supply-chain/orientation.md) (cosign / SLSA,
[ADR-042](../../adrs/042-isolated-build-provenance-slsa-l3.md)) runs **once**, at image *pull*: it verifies the
signature and provenance of the *bytes*, and steps aside. Both are point-in-time gates on *static* properties.

Now the container is running, and it's the *runtime behavior* that no manifest can describe. A signed,
fully-admission-compliant container — exactly the kind both gates wave through — can still be exploited through an
app vulnerability and then: spawn a shell, read `/etc/shadow`, write a new binary under `/usr/bin`, call `setuid(0)`
to escalate, or open an outbound connection to somewhere it has no business talking to. None of those are
expressible as pod *config*, so none are checkable at admission. That's the blind spot Falco
([ADR-045](../../adrs/045-falco-runtime-threat-detection.md), **Accepted**) fills — it is the **complement**, not a
replacement, for the gates.

In the [4 Cs of cloud-native security](https://kubernetes.io/docs/concepts/security/overview/) (Cloud, Cluster,
Container, Code), Falco owns the **Container-runtime-behavior** layer: the continuous watcher on what a running
container *does*.

And the one property that shapes everything downstream: **Falco is detection, not prevention.** It observes a
syscall and *emits an event*; it does not stop the syscall from completing. So unlike Kyverno — which has an
Audit→Enforce flip, a mode where it merely records versus a mode where it *rejects* — Falco has **no such flip**.
There is no "enforce" setting to reach for. It always, only, alerts. Enforcement is a human (or a future
automation) acting on that alert. Hold onto this: it's why the whole rollout is sequenced the way it is.

> **Quick check:** a container passes Kyverno *and* has a valid cosign signature, then gets popped and opens a
> reverse shell. Which of the two admission gates catches it? *(Neither — both already ran and stepped aside.
> This is Falco's job, at runtime.)*

## The mechanism: a syscall is the tap point

Every meaningful thing a process does — open a file, connect a socket, exec a program, change its UID — it does by
asking the kernel, through a **[syscall](https://man7.org/linux/man-pages/man2/syscalls.2.html)** (the
userspace↔kernel boundary; the one door every process *must* go through to touch the machine). A process can lie
in its logs, but it cannot touch a file or a socket without a syscall. So the syscall boundary is the one place
where behavior is *ground truth*. Falco taps it.

**How it taps** is a driver choice. The module exposes it as
[`driver_kind`](https://github.com/asanexample/platform/blob/main/infra/modules/falco/variables.tf), validated to
one of three:

- `kmod` — a classic loadable **kernel module**. Powerful, but it must be *built for the exact running kernel*;
  brittle across node-image upgrades.
- `ebpf` — a legacy [eBPF](https://ebpf.io/what-is-ebpf/) probe (safe, sandboxed in-kernel bytecode) that still
  needs a per-kernel build step.
- `modern_ebpf` — **CO-RE** ("Compile Once, Run Everywhere"): one probe compiled against a stable kernel ABI
  (BTF) that runs across kernel versions with **no build on the node at all**.

This platform runs **`modern_ebpf`** — hard-coded in both live units and the module default. The *why* is
specific to EKS on AL2023: CO-RE needs kernel ≥ 5.8, which the AL2023 6.x nodes satisfy, so we get portability
across node-image bumps **without** the kernel-module or driver-build fragility that would otherwise break on
every AMI upgrade. And crucially it **coexists with [Cilium](../foundations/deep-dive-the-cluster.md)**, which is
*also* eBPF: they attach to **different hook points** (Cilium at the networking datapath; Falco at the syscall
tracepoints), so there's no collision — two eBPF tenants, one kernel, no fight.

Why Falco and not the near-misses? [ADR-045](../../adrs/045-falco-runtime-threat-detection.md) weighed the field:
**Tetragon** (also eBPF, same Cilium project — but a low-level primitive that needs heavy policy authoring to reach
Falco's out-of-box detection parity); **GuardDuty Runtime Monitoring** (managed and easy, but per-vCPU priced, an
opaque non-tunable ruleset, and AWS-locked — wrong for an OSS-default platform); **Tracee** (similar approach,
smaller ecosystem). Falco won on a mature curated ruleset out of the box, the falcosidekick routing ecosystem,
CNCF-**graduated** status, and rules-as-code you actually control.

### Why a privileged DaemonSet

Syscalls are a **per-kernel, per-node** phenomenon — the probe can only see the syscalls happening on the kernel
it's attached to. So detection is inherently *per node*: Falco runs as a
**[DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)** — exactly one Falco pod per
node — with the eBPF privilege it needs to load probes. That's why it lives in its own dedicated `falco`
**namespace**, deliberately kept *out* of the tenant / PSA-restricted namespaces (a privileged eBPF pod could
never pass the `restricted` Pod Security Admission floor those namespaces enforce). And its tolerations are
`operator: Exists` — it tolerates **every** taint, so no node can hide from it. Coverage is the whole fleet or
it's a gap.

## The rules engine — and what this platform actually runs

Falco matches each syscall against a **[rules-as-code](https://falco.org/docs/concepts/rules/) ruleset**: a rule
is a condition over syscall fields, with a **priority** (`Debug` … `Notice` … `Warning` … `Critical`) and a set of
**tags** — including **[MITRE ATT&CK](https://attack.mitre.org/) technique IDs** so a firing maps to a known
adversary behavior. The module turns on `json_output` + `json_include_output_property` (see
[`main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/falco/main.tf)) so every event is
structured JSON with clean fields, ready for downstream routing.

Here is the honest, verify-it-yourself fact: **this platform runs the default upstream Falco ruleset, unchanged.**
There are **no custom rules** wired in. You can confirm it from the module's shape — it is *only*
`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`. No rules file, no `customRules` ConfigMap, no
values key mounting one. Whatever the stock chart ships is exactly what's detecting. That's a deliberate
starting point, and — as we'll see — it's the root of the tuning story.

## The worked example: what the stream says *right now*

Falco is **live on both clusters**. On the platform hub, the DaemonSet is `3/3` (one pod per node), up ~35h,
running Falco `0.44.0` via chart `9.0.0`:

```text
$ AWS_PROFILE=platform kubectl --context platform -n falco get pods,daemonset
NAME                                       READY   STATUS    RESTARTS   AGE
pod/falco-falcosidekick-6f5c4dc956-gxgxc   1/1     Running   0          12h
pod/falco-falcosidekick-6f5c4dc956-ttx9v   1/1     Running   0          12h
pod/falco-fcf2s                            2/2     Running   0          12h
pod/falco-jx6tv                            2/2     Running   0          12h
pod/falco-n5ncm                            2/2     Running   0          12h

NAME                   DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   AGE
daemonset.apps/falco   3         3         3       3            3           35h
```

Tail the Falco container and it is *actively emitting JSON events*. Here's a real one, pulled live (reformatted for
reading, values verbatim):

```json
{
  "priority": "Notice",
  "rule": "Contact K8S API Server From Container",
  "source": "syscall",
  "tags": ["T1565", "container", "k8s", "maturity_stable", "mitre_discovery", "network"],
  "output_fields": {
    "container.image.repository": "docker.io/tailscale/k8s-operator",
    "container.image.tag": "v1.96.5",
    "k8s.ns.name": "tailscale-system",
    "k8s.pod.name": "operator-5f88ff8bd5-…",
    "proc.name": "operator",
    "evt.type": "connect",
    "fd.name": "10.240.1.107:40360->172.20.0.1:443",
    "user.name": "root"
  }
}
```

Read it top to bottom and you can see the whole mechanism working: a `connect` syscall, from a process named
`operator`, running as `root`, in the `tailscale-system` namespace, reaching out to `172.20.0.1:443` — the
in-cluster Kubernetes API service (`kubernetes.default`). The stock rule **"Contact K8S API Server From
Container"** matched it, stamped it `Notice`, and tagged it `T1565` (MITRE *Data Manipulation*) under
`mitre_discovery`. A container talking to the API server *is*, in the abstract, exactly the reconnaissance move an
attacker makes after popping a pod.

Except here it's the **Tailscale operator** — a legitimate platform controller whose entire job is to talk to the
API server. And it's not alone: *any* in-cluster controller that calls the API trips the same rule, firing over
and over. **This is a false positive** — a stock rule doing precisely what it says, on behavior that is completely
normal for *this* cluster. Sit here and it becomes the headline lesson: **an untuned ruleset is a firehose of
true-to-the-letter, useless-in-context alerts.**

> *Back to the motion sensor.* A brand-new alarm, out of the box, trips on the cat, the ceiling fan, and the
> curtains in a draft. It's not broken — it's *untuned*. **Where it breaks:** unlike a home alarm you'd just
> arm anyway, arming this one (pointing it at a pager) before tuning means every on-call human learns, within a
> day, to ignore it. A muted-by-fatigue alarm is worse than no alarm.

**Quick check:** the event above is a *false positive*. Name the two things about it that make it look
exactly like a real attack. *(A non-system container, running as `root`, connecting to the API server — the
literal signature of post-exploitation recon. Only cluster context tells them apart.)*

## Falcosidekick — the alarm is wired to no one (on purpose)

So Falco *detects*. Who gets told? That's **falcosidekick**, the alert-routing fan-out layer. It **is** deployed —
`enable_falcosidekick` defaults `true`, and you can see the two `falco-falcosidekick` replicas `Running` above. But
here's the honest status, straight from its own startup log:

```text
$ AWS_PROFILE=platform kubectl --context platform -n falco logs deploy/falco-falcosidekick | grep -i output
2026/07/07 14:17:11 [INFO]  : Falcosidekick version: 2.32.0
2026/07/07 14:17:11 [INFO]  : Enabled Outputs: []
2026/07/07 14:17:11 [INFO]  : Falcosidekick is up and listening on :2801
```

**`Enabled Outputs: []`.** Both live units pass only `enable_falcosidekick = true` and *no* `falcosidekick_config`,
so falcosidekick has **zero output destinations**. It receives every event Falco produces and logs it to
**stdout** — and stops there. Nothing goes to Slack, no SNS topic, no dashboard. **Falco sees everything on both
clusters right now, and tells no one.** [ADR-045](../../adrs/045-falco-runtime-threat-detection.md) says this in as
many words: *"until falcosidekick → SNS/observability lands, nobody is paged."*

Where the alerts *will* go is designed but deferred (tracked under #116 / #102):

- **SNS** → the shared platform-alerts topic. The
  [`aws/sns-notifications`](https://github.com/asanexample/platform/blob/main/infra/modules/aws/sns-notifications/main.tf)
  module already *names* falcosidekick as an intended publisher — but the module creates **no IAM**; publishers
  self-grant `sns:Publish` on their own identity, and that grant for falcosidekick **is not wired yet**.
- **The [observability stack](../observability/orientation.md)** — so detections become alerts and dashboards.
  Verified: there is currently **no Falco alert or dashboard in any `observability*` module**.
- **Owner-routing / triage** — no connection to the triage agent yet.

The kicker: turning it on is a **one-variable change** — `falcosidekick_config = { sns = { topicarn = "…" } }`
in the unit, plus the publish grant. The plumbing is a value, not a rebuild.

## Tuning is the real cost — and why routing waits behind it

Now the two threads tie together. The default ruleset catches the genuinely bad — shell-in-a-container, a read of
`/etc/shadow`, a write below a binary dir, a `setuid` privilege escalation, an unexpected outbound connection, a
container escape, contact-the-API-from-a-container — each MITRE-tagged. But out of the box it *also* flags
legitimate platform behavior, as the live stream proves every second. **Tuning that ruleset to each cluster's real
behavior is the actual operational cost of Falco** — and [ADR-045](../../adrs/045-falco-runtime-threat-detection.md)
lists it as an explicit Negative and an open follow-up.

This is *why the rollout sequences detection before routing.* You run to **stdout first**, watch what actually
fires, and tune the known-good patterns *before* you point the alarm at a human. Wire SNS to an untuned firehose
and you've built an alert-fatigue machine on day one. Detect-to-stdout, then route-to-humans, then tune
continuously — it's the same "audit-first, enforce-later" instinct as Kyverno's Audit→Enforce, adapted to a tool
that *never* enforces: since Falco can't block, the analog of "flipping to Enforce" is simply *wiring the outputs*,
and you earn that by tuning first.

How you'd tune (the deferred work): extend the module to mount a **custom-rules** ConfigMap via the chart's
`customRules` values key — either a **new detection rule**, or (more commonly here) an **exception / macro** that
suppresses a known-good pattern, e.g. "allow the Tailscale operator in `tailscale-system` to contact the API
server." Each suppression is a small, reviewable, code-controlled diff — rules-as-code, the property Falco was
chosen *for*.

## Gotchas that teach

- **Falco caught something — did it stop it? No.** Detection, never prevention. There is no Enforce mode, no
  Audit→Enforce flip. Every finding is a signal for a human or an automation to act on; the syscall already
  completed. Design your response path accordingly.
- **A firing rule is not an incident.** The live "Contact K8S API Server From Container" on the Tailscale operator
  is a *true match on benign behavior*. Rule-fired ≠ malicious; only cluster context decides. Tune before you
  page, or on-call will train themselves to ignore Falco.
- **Falco can drop events under load.** The same live stream carries `"rule": "Falco internal: syscall event
  drop"` at `Debug` — e.g. *"215824 system calls dropped in last second."* Under a syscall storm the ring buffer
  overflows and Falco *misses* events. It's self-reported (watch that internal rule), but it means detection is
  best-effort, not a guarantee — size buffers / resources for busy nodes.
- **`Enabled Outputs: []` is the whole story on paging.** Before you assume "Falco will alert us," check
  falcosidekick's outputs. Today they're empty on both clusters — detection is live, paging is not.
- **eBPF is a two-tenant kernel.** Falco and Cilium are *both* eBPF. They coexist only because they hook different
  points; `modern_ebpf` (CO-RE, kernel ≥ 5.8, satisfied by AL2023 6.x) is what keeps Falco portable across node
  images without a per-kernel driver build. Change the node AMI to something older and this assumption is the
  first thing to re-check.

## Go deeper

**Source of truth (this platform):**

- [ADR-045 — Falco for Runtime Threat Detection](../../adrs/045-falco-runtime-threat-detection.md) — the decision,
  the rejected alternatives (Tetragon / GuardDuty / Tracee), and the honest staged rollout.
- The [`falco` module](https://github.com/asanexample/platform/blob/main/infra/modules/falco/main.tf) —
  `main.tf` (values), [`variables.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/falco/variables.tf)
  (`driver_kind`, `falcosidekick_config`). Live units:
  [platform](https://github.com/asanexample/platform/blob/main/infra/live/aws/platform/us-east-1/platform/falco/terragrunt.hcl)
  / [preprod](https://github.com/asanexample/platform/blob/main/infra/live/aws/preprod/us-east-1/platform/falco/terragrunt.hcl).
- The intended sink:
  [`aws/sns-notifications`](https://github.com/asanexample/platform/blob/main/infra/modules/aws/sns-notifications/main.tf)
  (names falcosidekick as a publisher; self-grant not wired).

**The gates Falco complements:** [Policy & admission](../policy/orientation.md) (Kyverno, the door),
[Supply chain](../supply-chain/orientation.md) (signed images, the ID check), and back to the
[runtime-security orientation](orientation.md) and its [reference](reference.md).

**Substrate (external, canonical, verified):**

- [Falco docs](https://falco.org/docs/) — the project's own documentation. *~30 min to orient.*
- [Falco rules](https://falco.org/docs/concepts/rules/) — how a rule (condition + priority + tags) is written; the
  shape you'd extend when tuning. *~15 min.*
- [Falco kernel event sources](https://falco.org/docs/concepts/event-sources/kernel/) — the driver options
  (`kmod` / `ebpf` / `modern_ebpf`) in the maintainer's words. *~10 min.*
- [falcosidekick](https://github.com/falcosecurity/falcosidekick) — the routing layer and its full output catalog
  (what `falcosidekick_config` can point at). *~10 min.*
- [What is eBPF?](https://ebpf.io/what-is-ebpf/) — the substrate both Falco and Cilium ride. *~15 min.*
- [MITRE ATT&CK T1565](https://attack.mitre.org/techniques/T1565/) — the technique the live example is tagged
  with. *~5 min.*
