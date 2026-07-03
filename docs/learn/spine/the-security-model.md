# The Security Model

> **A spine doc — the map, read through a threat lens, top to bottom.**
> [How the Platform Fits](how-the-platform-fits.md) showed the layers as an *operating system*; this shows
> the same layers as *concentric defenses*, across the whole stack — cloud, cluster, container, and code —
> and, because it's a security doc, it is **relentlessly honest about the gaps.** A wall of green
> checkmarks is exactly what a real attacker hopes you'll write. Long, and it should be.

## The question

Everything so far was framed around *shipping software*. Now the adversary's version: **if someone wanted
to steal `alpha`'s data or take over the cluster, what actually stops them — at every level — and where are
the holes we already know about?** A security model that only covers one layer (say, workloads) while
staying quiet about the cloud account, the cluster, the application code, and the things we *haven't built
yet* isn't a security model; it's a comfort blanket. So this one goes top to bottom, and it keeps a running
tally of what's missing.

## The one idea: defense in depth, in two dimensions

Security here isn't a feature bolted on — it's a **property of the layers**, and it works because the layers
are independent. You already saw why in [How the Platform Fits](how-the-platform-fits.md): almost every
control plane is *also* a security control. Defense in depth means *many independent walls*, arranged so an
attacker must defeat all of them.

The industry's standard way to organize those walls is the **[4 C's of cloud-native security](https://kubernetes.io/docs/concepts/security/overview/)** —
concentric layers, outermost first:

> **Cloud → Cluster → Container → Code.** Each layer is secured *on top of* the one outside it. Weak cloud
> security can't be rescued by strong container security; the layers compound, they don't substitute.

And there's a *second* axis, orthogonal to the first — **time**. The same concern is defended at three
moments: **shift-left** (caught in CI, before it exists), **at admission** (blocked at the cluster door),
and **at runtime** (detected while running). Depth *and* time.

> The mental model for why independent layers matter is the **Swiss cheese model** (James Reason, safety
> engineering): each layer is a slice with *holes* — no control is perfect — but the holes are in different
> places, so a threat only lands if the holes align across *every* slice at once. **Where it breaks:** real
> holes are fixed; ours move — a misconfiguration can suddenly align holes that were safely offset. Which is
> why the honest gaps register near the end is load-bearing, not an afterthought.

Below, each layer is walked with its defenses tagged **built**, **partial**, or **gap** (designed or absent).

## Cloud — the AWS layer

The outermost wall, enforced below anything we run.

- **Account isolation + SCPs** *(built)* — preprod, prod, platform, and mgmt are separate AWS accounts;
  an attacker who owns preprod **cannot** reach prod (AWS enforces the boundary). Service Control Policies
  ([ADR-003](../../adrs/003-scp-design-philosophy.md)) make whole *categories* of action impossible
  org-wide.
- **Least-privilege IAM + a permissions boundary** *(built)* — roles hold the minimum they need, and
  every *environment* IAM role is capped by a **permissions boundary** — an outer limit on what it can
  *ever* do, regardless of what policy gets attached. A compromised environment can't escalate past its box.
- **Encryption + keys** *(built)* — KMS-managed keys; secrets are encrypted at rest, including
  **EKS secrets envelope-encrypted** in etcd.
- **Audit** *(partial)* — [CloudTrail](../../adrs/037-cloudtrail-audit-logging.md) records API activity on
  the secrets/KMS path. But **cloud-native threat detection is a gap:** no **GuardDuty** (anomaly
  detection), no **AWS Config / Security Hub** (continuous posture/CSPM), no **Inspector** (resource vuln
  scanning), no **Macie** (sensitive-data discovery). We have the isolation walls; we don't yet have the
  cloud-level *alarms*.
- **Edge protection** *(gap)* — **no AWS WAF** and no managed DDoS/Shield posture. Public ingress is TLS'd
  and hostname-scoped, but there's no web-application firewall inspecting requests for attack patterns.

## Cluster — the Kubernetes layer

- **Private API** *(built)* — the cluster API is [private-only](../../adrs/010-private-eks-api-endpoint.md),
  reached over Tailscale, never the public internet.
- **RBAC** *(built)* — least-privilege, per-team ([ADR-039](../../adrs/039-per-team-developer-rbac.md)); the
  platform-engineer access model is read-and-operate, not author
  ([ADR-040](../../adrs/040-platform-engineer-access-model.md)).
- **Pod Security Admission** *(built)* — the PSA **baseline** floor sits *under* Kyverno as a native
  backstop, so even a policy gap can't admit a wildly privileged pod.
- **Admission control — [Kyverno](https://kyverno.io/docs/)** *(built, Enforce)* — rejects non-compliant
  workloads at the door (registry, limits, probes, hostnames, no-privileged), on preprod and platform.
- **Network policy — Cilium** *(built)* — default-restricted pod-to-pod traffic; a compromised pod can't
  freely roam the cluster.
- **Runtime detection — [Falco](https://falco.org/)** *(partial)* — watches syscalls on the environment
  clusters and alerts on suspicious behavior (a shell in a container, a read of a sensitive path). Live on
  preprod; coverage and tuning still maturing — and it's *detection*, not prevention.
- **Gaps** — **east-west mTLS** is designed, not built
  ([ADR-057](../../adrs/057-service-identity-and-east-west-zero-trust.md)): pods are restricted by *policy*
  but don't yet cryptographically prove identity to each other. **EKS API audit logging isn't fully on**
  (thin cluster forensics). No **CIS Kubernetes Benchmark / kube-bench** scanning or hardened-AMI program
  yet. WireGuard pod-level encryption is backlog.

> **Quick check:** Kyverno enforces admission policy — so why *also* run Pod Security Admission underneath
> it? *(Defense in depth at one layer: PSA is a native Kubernetes backstop, so a Kyverno outage or policy
> gap still can't admit a wildly privileged pod. Two independent slices, holes offset.)*

## Container — the image & workload layer

- **Signed + attested images** *(built)* — every image is **cosign-signed** and carries **SLSA provenance**
  ([ADR-042](../../adrs/042-isolated-build-provenance-slsa-l3.md) /
  [ADR-050](../../adrs/050-shared-build-sign-reusable-workflow.md)), and Kyverno **re-verifies at
  admission** — the cluster won't run an unsigned image. This defeats image *substitution*.
- **Vulnerability scanning** *(built)* — **Trivy** scans images and dependencies in CI, and **ECR
  scan-on-push** re-scans in the registry. Known-CVE dependencies get flagged.
- **Hardened runtime context** *(built)* — Kyverno mutates in the safe defaults (drop all capabilities, no
  privilege escalation, seccomp `RuntimeDefault`, non-root where declared); regulated tiers add
  `runAsNonRoot` + `readOnlyRootFilesystem`.
- **Immutability** *(built)* — deploys are pinned to an image **digest**, not a mutable tag.
- **Gaps** — base-image *currency* (rebuilding on upstream CVE) and distroless/minimal-base enforcement are
  partial; there's no automatic "block deploy on critical CVE" gate wired end-to-end yet.

## Code — the application layer

Where **[OWASP Top 10](https://owasp.org/www-project-top-ten/)** risks live — injection, broken access
control, XSS, and friends. This is the layer most dependent on the *app team*, and the platform's job is to
give them strong shift-left tooling.

- **SAST — Semgrep** *(built)* — static analysis runs in CI, catching code-level security bugs (a class of
  OWASP issues) before merge, results published as SARIF.
- **SCA — Trivy + Dependabot** *(built)* — dependency vulnerability scanning in CI plus automated
  dependency-update PRs.
- **CI/CD supply-chain hardening** *(built)* — GitHub Actions are **pinned to SHAs** and installed with
  checksum verification; **fail-closed governance gates** guard every registry/roles/people/teams change;
  `main` is protected, changes are reviewed.
- **Policy shift-left** *(built)* — the *same* Kyverno policies that enforce at admission also run as a
  **Kyverno CLI** check in CI, so a non-compliant manifest fails the PR, not the deploy.
- **Gaps** — **no secret scanning** (gitleaks-style) in CI — we rely on SOPS discipline + review, which is
  weaker than a scanner. **No DAST** (dynamic/running-app testing). And, tying back to Cloud: **no WAF** to
  blunt OWASP-class attacks against *running* apps at the edge. App-layer runtime defense is the thinnest
  part of the model today.

> **Quick check:** name where the *same* image is checked at three different times. *(Its dependencies are
> scanned by Trivy in **CI** (shift-left); its signature is verified by Kyverno at **admission**; its
> behavior is watched by Falco at **runtime**. One artifact, three moments — that's the time axis.)*

## Security across time — shift-left, enforce, detect

Step back from the layers and look along the timeline. The platform defends the same concerns at three
moments, and the *earlier* it catches something, the cheaper the fix:

- **Shift-left (in CI, before it exists):** Semgrep, Trivy, the Kyverno CLI, TFLint, `tofu validate` — a
  problem caught here never reaches a cluster.
- **At admission (at the door):** Kyverno + PSA + signature verification — a problem that slipped past CI is
  *blocked* before it runs.
- **At runtime (while running):** Falco + network policy + least-privilege scope — a problem that got in is
  *detected and contained*.

Catch early, enforce at the door, detect what slips past. Missing any one moment isn't fatal — that's the
point of depth — but the gaps register shows the runtime moment (WAF, DAST, full audit) is our thinnest.

## Watch the layers hold — a concrete threat

Walk a real one. An attacker **compromises a dependency** `shop` pulls in — malicious code in a library
`shop`'s own devs merge unknowingly.

1. **Code / CI — a partial catch.** If the poisoned dependency has a *known* CVE, **Trivy** flags it in CI
   and the PR fails — caught, shift-left. But if it's a *novel* or deliberately-hidden payload, Trivy and
   Semgrep have nothing to match, and it passes. **This slice has a hole for a targeted supply-chain
   attack** — pretending otherwise would be the dishonest kind of security.
2. **Container / admission — it passes.** CI builds and *signs* the image; the signature is genuinely valid
   (it *did* come from `shop`'s repo). Kyverno's signature check passes, because signing proves *origin*,
   not *innocence*. The malicious code deploys. One slice's holes have lined up.
3. **The other slices hold.** Now the code tries to steal data and spread:
   - **Least privilege / Pod Identity:** it has only `shop`'s scoped AWS role — its own bucket, not other
     teams' data, not platform roles.
   - **Network policy:** it can only reach what Cilium allows — no free exfiltration path.
   - **Account boundary:** total control of `shop-dev` still **cannot** touch prod — different account.
   - **No standing secrets:** no long-lived keys in the image to harvest.
   - **Runtime (Falco):** spawning a shell or reading a sensitive path trips an alert.

One slice failed completely; the breach was still *contained*, because least privilege, network policy,
account isolation, and runtime detection are independent walls whose holes didn't align. **That** is defense
in depth — not "every layer is perfect," but "no single failure is fatal."

## The two principles underneath everything

- **Least privilege** — every identity, human or workload, gets the *minimum* it needs, most of it only
  *briefly*. A poisoned `shop` pod can hurt `shop`, not the platform.
  ([NIST](https://csrc.nist.gov/glossary/term/least_privilege).)
- **Zero standing trust** — nothing is trusted *by default* or *permanently*: no long-lived keys (Pod
  Identity is short-lived), no standing admin (temporary-power expires,
  [ADR-088](../../adrs/088-temporary-power-activation.md)), no unsigned image, no implicit network reach, no
  imperative cluster access. Earned, scoped, time-boxed — the instinct of
  [NIST Zero Trust (SP 800-207)](https://csrc.nist.gov/pubs/sp/800/207/final).

## The gaps register — what we do *not* claim

The most important section. A posture you can trust is one that names its own holes. As of today:

| Layer | Gap | Why it matters |
| --- | --- | --- |
| **Cloud** | No **WAF** / managed DDoS | No edge inspection of requests for OWASP-class attack patterns |
| **Cloud** | No **GuardDuty / Config / Security Hub / Inspector / Macie** | Isolation walls exist, but no cloud-level threat *detection* or continuous posture/CSPM |
| **Cluster** | **East-west mTLS** designed, not built ([ADR-057](../../adrs/057-service-identity-and-east-west-zero-trust.md)) | Pods restricted by policy but don't cryptographically verify each other |
| **Cluster** | **EKS API audit logging** not fully on | Thin cluster-API forensics after an incident |
| **Cluster** | No **CIS benchmark / kube-bench** or hardened-AMI program | Node/cluster hardening isn't measured against a standard |
| **Container** | No end-to-end **block-on-critical-CVE** gate; base-image currency partial | A known-vulnerable image can still deploy |
| **Code** | No **secret scanning** (gitleaks) in CI | Relies on SOPS discipline + review, not a scanner |
| **Code** | No **DAST**; app-layer (OWASP) runtime defense thin | Running-app vulnerabilities aren't actively tested or shielded |
| **Cross-cutting** | **Secrets rotation** not automated | Secrets are encrypted + isolated, but rotating them is manual |
| **Cross-cutting** | No **SIEM** / central security-event aggregation | Signals exist (SARIF, CloudTrail, observability) but aren't correlated in one place |
| **Cross-cutting** | No **pentest / red-team** program; **compliance evidence** aspirational ([ADR-055](../../adrs/055-compliance-assurance-and-continuous-control-evidence.md)) | Controls aren't adversarially validated or attested |
| **Cross-cutting** | **Backup / DR** partial (CNPG no-backup, [ADR-054](../../adrs/054-platform-resilience-and-business-continuity.md)) | Ransomware/data-loss resilience incomplete |

None of these are secrets — they're tracked and prioritized in
[epic #1152](https://github.com/asanexample/platform/issues/1152), and naming them *is* the maturity signal.
**A platform that claims perfect security is telling you it hasn't looked hard enough.**

## Where this model comes from

Textbook, deliberately:

- **The 4 C's (Cloud/Cluster/Container/Code)** —
  [Kubernetes security overview](https://kubernetes.io/docs/concepts/security/overview/) and the
  [CNCF Cloud Native Security Whitepaper](https://www.cncf.io/reports/cloud-native-security-whitepaper/).
- **App-layer risks** — the [OWASP Top 10](https://owasp.org/www-project-top-ten/).
- **Defense in depth · least privilege · zero standing trust** —
  [NIST](https://csrc.nist.gov/glossary/term/defense_in_depth) ·
  [least privilege](https://csrc.nist.gov/glossary/term/least_privilege) ·
  [NIST Zero Trust (SP 800-207)](https://csrc.nist.gov/pubs/sp/800/207/final).
- **Supply-chain integrity** — [SLSA](https://slsa.dev/spec/v1.0/threats) +
  [Sigstore/cosign](https://docs.sigstore.dev/cosign/signing/overview/).
- **Cloud foundation** — [AWS Security pillar](https://aws.amazon.com/architecture/security-identity-compliance/).
- The **Swiss cheese model** of layered defense — James Reason, safety engineering.

## Recap — say it back

Try it cold: *what secures this platform, top to bottom — and what does it not yet claim?* If you can say —

> "**Defense in depth across the 4 C's** — **Cloud** (account isolation, SCPs, least-privilege IAM with
> permissions boundaries, KMS) → **Cluster** (private API, RBAC, PSA + Kyverno, Cilium, Falco) →
> **Container** (signed + scanned + hardened + digest-pinned) → **Code** (SAST, SCA, pinned CI,
> policy-shift-left) — and across **time** (shift-left → enforce at admission → detect at runtime). No wall
> is perfect — a novel poisoned dependency passes signing — but the walls are *independent*, so a breach is
> **contained**. And honestly, **WAF, GuardDuty/CSPM, east-west mTLS, secret-scanning, DAST, full audit
> logging, secrets rotation, a SIEM, and pentesting are gaps we *name*, not hide**" —

— then you understand the platform's security *and* its maturity: the honest posture, not the
green-checkmark one.

## Go deeper

- The same layers as an *operating system*: [How the Platform Fits](how-the-platform-fits.md). The signing
  and admission walls in motion: [The Life of a Deployment](life-of-a-deployment.md).
- As full modules *(coming — [inventory](../_inventory.md))*: Policy & admission, Supply chain, Identity &
  access, and the honest **Compliance & regulated workloads** placeholder.
- The canon:
  [4 C's / K8s security](https://kubernetes.io/docs/concepts/security/overview/) ·
  [CNCF Cloud Native Security](https://www.cncf.io/reports/cloud-native-security-whitepaper/) ·
  [OWASP Top 10](https://owasp.org/www-project-top-ten/) ·
  [NIST Zero Trust](https://csrc.nist.gov/pubs/sp/800/207/final) ·
  [SLSA](https://slsa.dev/spec/v1.0/threats).
