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
tally of what's missing. (It's a *living* tally — a few gaps in earlier drafts of this page have since been
closed, and they're marked as such below. A security posture is a moving state, not a monument.)

## The one idea: defense in depth, in two dimensions

Security here isn't a feature bolted on — it's a **property of the layers**, and it works because the layers
are independent. You already saw why in [How the Platform Fits](how-the-platform-fits.md): almost every
control plane is *also* a security control. The admission gate that enforces resource limits also rejects
unsigned images; the Pod Identity that hands out AWS credentials also refuses to mint long-lived keys; the
account boundary that contains a *deployment's* blast radius also contains an *attacker's*. We never built a
separate "security system" — security **falls out of the layering**. Defense in depth means *many
independent walls*, arranged so an attacker must defeat all of them in sequence.

The industry's standard way to organize those walls is the **[4 C's of cloud-native security](https://kubernetes.io/docs/concepts/security/overview/)** —
concentric layers, outermost first:

> **Cloud → Cluster → Container → Code.** Each layer is secured *on top of* the one outside it. Weak cloud
> security can't be rescued by strong container security; the layers compound, they don't substitute.

And there's a *second* axis, orthogonal to the first — **time**. The same concern is defended at three
moments: **shift-left** (caught in CI, before it exists), **at admission** (blocked at the cluster door),
and **at runtime** (detected while running). Depth *and* time — a grid, not a line.

> The mental model for why independent layers matter is the **Swiss cheese model** (James Reason, safety
> engineering): each layer is a slice with *holes* — no control is perfect — but the holes are in different
> places, so a threat only lands if the holes align across *every* slice at once. You don't build security
> by finding one flawless slice; you build it by *stacking imperfect slices whose holes don't line up.*
> **Where it breaks:** real cheese holes are fixed; ours *move* — a misconfiguration can suddenly align
> holes that were safely offset yesterday. Which is why the honest gaps register near the end is
> load-bearing, not an afterthought.

Below, each layer is walked with its defenses tagged **built**, **partial**, or **gap** (designed or absent).

## Cloud — the AWS layer

The outermost wall, and the strongest, because it's enforced *below* anything we run — by AWS itself, not by
software we operate.

- **Account isolation + SCPs** *(built)* — preprod, prod, platform, and mgmt are *separate AWS accounts*.
  An attacker who completely owns preprod **cannot** reach prod — not "shouldn't," *can't*: the account is
  AWS's hardest isolation boundary (separate IAM, billing, resources), and cross-account access is
  deny-by-default. On top of that, **Service Control Policies**
  ([ADR-003](../../adrs/003-scp-design-philosophy.md)) make whole *categories* of action impossible
  org-wide — a guardrail even a compromised account-admin can't step over, because it's enforced at the
  organization root above the account.
- **Least-privilege IAM + a permissions boundary** *(built)* — every role holds the minimum it needs. And
  every *environment* IAM role is additionally capped by a **permissions boundary** — a distinct AWS
  mechanism worth understanding: a policy *can't* grant more than the boundary allows, no matter what gets
  attached later. So even if an attacker could edit an environment's role policy, the boundary is an outer
  fence they can't move. Grant-time least-privilege *plus* a hard ceiling.
- **Encryption + keys** *(built)* — KMS-managed keys throughout; data is encrypted at rest, including
  **EKS Secrets envelope-encrypted** in etcd (so a raw etcd read yields ciphertext, not secrets).
- **Audit** *(partial)* — [CloudTrail](../../adrs/037-cloudtrail-audit-logging.md) records API activity on
  the secrets/KMS path. But **cloud-native threat *detection* is a gap:** no **GuardDuty** (behavioral
  anomaly detection), no **AWS Config / Security Hub** (continuous posture / CSPM), no **Inspector**
  (resource vuln scanning), no **Macie** (sensitive-data discovery). We have the isolation *walls*; we don't
  yet have the cloud-level *alarms* — a deliberate cost trade-off (these are usage-priced and can be
  expensive), tracked, not forgotten.
- **Edge protection** *(gap)* — **no AWS WAF** and no managed DDoS/Shield posture. Public ingress is TLS'd
  and hostname-scoped, but nothing inspects request *content* for attack patterns (injection, path
  traversal, bad bots). This is the same hole that shows up at the Code layer, seen from outside.

> **Quick check:** an SCP and a permissions boundary both "limit what a role can do" — how do they differ?
> *(An SCP is org-level and applies to a whole account, enforced above it; a permissions boundary is
> attached to an individual IAM role as a ceiling on its own policies. Two independent limits at two
> altitudes — both have to be passed.)*

## Cluster — the Kubernetes layer

- **Private API** *(built)* — the cluster API is [private-only](../../adrs/010-private-eks-api-endpoint.md),
  reached over Tailscale, *never* the public internet. The single most-attacked surface of a Kubernetes
  cluster simply isn't on the internet to attack.
- **RBAC** *(built)* — least-privilege, per-team ([ADR-039](../../adrs/039-per-team-developer-rbac.md)); the
  platform-engineer access model itself is *read-and-operate, not author*
  ([ADR-040](../../adrs/040-platform-engineer-access-model.md)) — even operators don't hold standing
  authority to rewrite the cluster; that goes through GitOps.
- **Pod Security Admission** *(built)* — the PSA **baseline** floor sits *underneath* Kyverno as a native
  Kubernetes backstop. This is defense-in-depth *within one layer*: even a Kyverno outage or a policy gap
  can't admit a wildly privileged pod, because PSA is a second, independent slice.
- **Admission control — [Kyverno](https://kyverno.io/docs/)** *(built, Enforce)* — the policy engine on the
  cluster door, rejecting non-compliant workloads on preprod and platform (wrong registry, missing limits or
  probes, disallowed hostnames, privileged containers). Policy-as-code: the rules that used to live in a
  reviewer's head are executable and identical every time.
- **Network policy — Cilium** *(built)* — pod-to-pod traffic is default-restricted, so a compromised pod
  can't freely roam the cluster. **And, new: pods are explicitly denied egress to the instance-metadata
  service (IMDS)** *(built, live on preprod)* — a `deny-imds-egress` policy in every environment namespace
  closes a classic credential-theft / SSRF path, so IMDS protection no longer rests solely on the node's
  IMDSv2 hop-limit.
- **CIS benchmark scanning** *(built, preprod)* — **kube-bench** runs the CIS EKS Benchmark on a schedule
  and surfaces findings, so cluster hardening is now *measured against a standard* rather than assumed.
  *(The scan is live; acting on findings and hardened-AMI adoption are the remaining half.)*
- **Runtime detection — [Falco](https://falco.org/)** *(partial)* — watches syscalls on the environment
  clusters and alerts on suspicious behavior (a shell spawned in a container, a read of a sensitive path).
  Live on preprod; coverage and alert-tuning still maturing — and it's *detection*, not prevention.
- **East-west encryption + mutual auth — [Cilium](https://cilium.io/) WireGuard + SPIFFE/SPIRE** *(built)* —
  the "east-west" (service-to-service) half of zero trust ([ADR-057](../../adrs/057-service-identity-and-east-west-zero-trust.md)).
  Pod-to-pod traffic is transparently encrypted on the wire (**WireGuard**, live on *both* clusters — no app
  changes), and Cilium **mutual authentication** with an embedded **SPIRE** issues a per-workload **SPIFFE**
  identity so services *cryptographically prove who they are* to each other — not just "restricted by policy."
  Live as a showcase on preprod: the `alpha-shop → alpha-checkout` call is SPIRE-mutually-authenticated
  (`AUTH TYPE=spire`), a cross-team impostor is denied. *Fleet-wide, tier-gated enforcement is the remaining half.*
- **Gaps** — **EKS API audit logging** isn't fully on (a cost trade-off — the logs are CloudWatch-only and
  high-volume), leaving cluster forensics thin. Hardened-AMI adoption is backlog.

> **Quick check:** Kyverno already enforces admission policy — so why *also* run Pod Security Admission
> underneath it? *(Defense in depth at a single layer: PSA is a native backstop, so a Kyverno outage or
> policy gap still can't admit a wildly privileged pod. Two independent slices, holes offset — the same
> reason the account boundary sits under the network policy.)*

## Container — the image & workload layer

- **Signed + attested images** *(built)* — every image is **cosign-signed** and carries **SLSA provenance**
  ([ADR-042](../../adrs/042-isolated-build-provenance-slsa-l3.md) /
  [ADR-050](../../adrs/050-shared-build-sign-reusable-workflow.md)), and Kyverno **re-verifies at
  admission** — trust is checked at the moment of *use*, not taken on faith from the registry. This defeats
  image *substitution* (swapping a malicious blob under a trusted name).
- **Vulnerability scanning** *(built)* — **Trivy** scans dependencies and Dockerfile config in CI, and
  **ECR scan-on-push** scans the built image in the registry, so a known CVE is flagged before *and* after
  it lands.
- **Hardened runtime context** *(built)* — Kyverno *mutates in* the safe defaults so developers can't forget
  them: drop all Linux capabilities, no privilege escalation, `seccomp: RuntimeDefault`, non-root where
  declared; regulated tiers additionally force `runAsNonRoot` + `readOnlyRootFilesystem`. The safe container
  is the *default* container.
- **Immutability** *(built)* — deploys are pinned to an image **digest**, not a mutable tag — you can't
  swap what `:latest` points at under a running service.
- **Gaps** — base-image *currency* (auto-rebuild on an upstream CVE) and distroless/minimal-base enforcement
  are partial, and there's no end-to-end "block deploy on critical CVE" gate yet — so a *known*-vulnerable
  image can still technically deploy.

> **Quick check:** name where the *same* image is checked at three different times. *(Its dependencies are
> scanned by Trivy in **CI** (shift-left); its signature is re-verified by Kyverno at **admission**; its
> runtime behavior is watched by Falco at **runtime**. One artifact, three moments — that's the time axis,
> and it's why a single missed check isn't fatal.)*

## Code — the application layer

Where **[OWASP Top 10](https://owasp.org/www-project-top-ten/)** risks live — injection, broken access
control, XSS, and friends. This is the layer most dependent on the *app team*, so the platform's job is to
hand them strong shift-left tooling that runs automatically.

- **SAST — Semgrep** *(built)* — static analysis runs in CI, catching a class of code-level security bugs
  (a slice of the OWASP Top 10) before merge; results published as SARIF.
- **SCA — Trivy + Dependabot** *(built)* — dependency vulnerability scanning in CI, plus automated
  dependency-update PRs so the fix arrives as a reviewable change.
- **Secret scanning — gitleaks** *(built, live)* — a fail-closed CI job (plus a pre-commit hook) scans full
  history for committed credentials, with a tight allowlist for the *deliberately* committed SOPS
  ciphertext. So "someone pasted a key into a file" is caught by a scanner, not just by review — closing a
  gap this page used to list.
- **CI/CD supply-chain hardening** *(built)* — GitHub Actions are **pinned to SHAs** and installed with
  checksum verification; **fail-closed governance gates** guard every registry/roles/people/teams change;
  `main` is protected, and changes are reviewed. The *pipeline itself* is a hardened surface.
- **Policy shift-left** *(built)* — the app CI validates each overlay *builds* namespace- and host-agnostic
  and product-scoped (a `kubectl kustomize` render plus checks for hardcoded namespaces, host placeholders,
  and cross-product images), so obvious violations surface in the PR. Kyverno itself enforces at admission;
  the Kyverno CLI runs in CI over the *policy module's own* test suite, keeping the rules honest.
- **Gaps** — **no DAST** (dynamic/running-app testing), and — tying back to Cloud — **no WAF** to blunt
  OWASP-class attacks against *running* apps at the edge. App-layer *runtime* defense (as opposed to the
  strong shift-left tooling above) is the thinnest part of the model today.

## Security across time — shift-left, enforce, detect

Step back from the layers and look along the timeline. The platform defends the same concerns at three
moments, and the *earlier* it catches something, the cheaper the fix:

- **Shift-left (in CI, before it exists):** Semgrep, Trivy, gitleaks, the Kyverno CLI, TFLint, `tofu
  validate` — a problem caught here never reaches a cluster.
- **At admission (at the door):** Kyverno + PSA + signature verification — a problem that slipped past CI is
  *blocked* before it runs.
- **At runtime (while running):** Falco + network policy (incl. the IMDS deny) + least-privilege scope — a
  problem that got in is *detected and contained*.

Catch early, enforce at the door, detect what slips past. Missing any one moment isn't fatal — that's the
point of depth — but the gaps register shows the runtime moment (WAF, DAST, full audit) is still our
thinnest.

## Watch the layers hold — a concrete threat

Walk a real one. An attacker **compromises a dependency** `shop` pulls in — malicious code in a library
`shop`'s own devs merge unknowingly.

1. **Code / CI — a partial catch.** If the poisoned dependency has a *known* CVE, **Trivy** flags it in CI
   and the PR fails — caught, shift-left. But if it's a *novel* or deliberately-hidden payload, Trivy,
   Semgrep, and gitleaks have nothing to match, and it passes. **This slice has a hole for a targeted
   supply-chain attack** — pretending otherwise would be the dishonest kind of security.
2. **Container / admission — it passes.** CI builds and *signs* the image; the signature is genuinely valid
   (it *did* come from `shop`'s repo). Kyverno's signature check passes, because signing proves *origin*,
   not *innocence*. The malicious code deploys. One slice's holes have lined up.
3. **The other slices hold.** Now the code tries to steal data and spread:
   - **Least privilege / Pod Identity:** it has only `shop`'s scoped AWS role — its own bucket, not other
     teams' data, not platform roles.
   - **IMDS deny + no standing secrets:** it can't reach the metadata service to harvest node credentials,
     and there are no long-lived keys baked into the image to steal.
   - **Network policy:** it can only reach what Cilium allows — no free exfiltration path.
   - **Account boundary:** total control of `shop-dev` still **cannot** touch prod — different AWS account.
   - **Runtime (Falco):** spawning a shell or reading a sensitive path trips an alert.

One slice failed completely; the breach was still *contained*, because least privilege, the IMDS deny,
network policy, account isolation, and runtime detection are independent walls whose holes didn't align.
**That** is defense in depth — not "every layer is perfect," but "no single failure is fatal."

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
| **Cloud** | No **GuardDuty / Config / Security Hub / Inspector / Macie** | Isolation walls exist, but no cloud-level threat *detection* or continuous posture/CSPM (a cost trade-off) |
| **Cluster** | **East-west mutual auth not yet fleet-enforced** — encryption is fleet-wide; mutual auth (SPIFFE/SPIRE, [ADR-057](../../adrs/057-service-identity-and-east-west-zero-trust.md)) is a **preprod showcase** | Every service *can* be cryptographically authenticated (proven on alpha-shop↔alpha-checkout), but `authentication.mode: required` policies aren't yet applied fleet-wide per tier |
| **Cluster** | **EKS API audit logging** not fully on | Thin cluster-API forensics after an incident (CloudWatch cost trade-off) |
| **Cluster** | No **hardened-AMI** program; kube-bench findings not yet remediated | The CIS *scan* now runs, but node hardening isn't complete |
| **Container** | No end-to-end **block-on-critical-CVE** gate; base-image currency partial | A known-vulnerable image can still deploy |
| **Code** | No **DAST**; app-layer (OWASP) runtime defense thin | Running-app vulnerabilities aren't actively tested or shielded |
| **Cross-cutting** | **Secrets rotation** not automated | Secrets are encrypted + isolated, but rotating them is manual |
| **Cross-cutting** | No **SIEM** / central security-event aggregation | Signals exist (SARIF, CloudTrail, observability) but aren't correlated in one place |
| **Cross-cutting** | No **pentest / red-team** program; **compliance evidence** aspirational ([ADR-055](../../adrs/055-compliance-assurance-and-continuous-control-evidence.md)) | Controls aren't adversarially validated or attested |
| **Cross-cutting** | **Backup / DR** partial — no tested restore/DR drills, no cross-region copy, RTO/RPO unvalidated ([ADR-054](../../adrs/054-platform-resilience-and-business-continuity.md)) | CNPG databases are backed up (WAL + PITR to S3), but recovery hasn't been rehearsed and non-CNPG data isn't covered |

*Recently closed (were on this list): **secret scanning** (gitleaks now in CI), the **CIS benchmark scan**
(kube-bench, preprod), **explicit IMDS egress deny** (live in every environment namespace), and **CNPG
database backups** (WAL archiving + PITR to S3, live on all platform-hub clusters).*

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

> "**Defense in depth across the 4 C's** — **Cloud** (separate accounts, SCPs, least-privilege IAM with
> permissions boundaries, KMS) → **Cluster** (private API, RBAC, PSA + Kyverno, Cilium network policy incl.
> an IMDS deny, WireGuard east-west encryption + SPIFFE mutual auth, kube-bench, Falco) → **Container** (signed + scanned + hardened + digest-pinned) → **Code**
> (SAST, SCA, secret-scanning, pinned CI, policy-shift-left) — and across **time** (shift-left → enforce at
> admission → detect at runtime). No wall is perfect — a novel poisoned dependency passes signing — but the
> walls are *independent*, so a breach is **contained**. And honestly, **WAF, GuardDuty/CSPM, DAST, full
> audit logging, secrets rotation, a SIEM, fleet-wide east-west mTLS enforcement, and pentesting are gaps we
> *name*, not hide**" —

— then you understand the platform's security *and* its maturity: the honest posture, not the
green-checkmark one.

## Go deeper

- The same layers as an *operating system*: [How the Platform Fits](how-the-platform-fits.md). The signing
  and admission walls in motion: [The Life of a Deployment](life-of-a-deployment.md).
- As full modules: [Policy & admission](../policy/orientation.md) ·
  [Identity & access](../identity/orientation.md) · [Supply chain](../supply-chain/orientation.md) *(built)* ·
  *(coming — [inventory](../_inventory.md))* the honest **Compliance & regulated workloads** placeholder.
- The canon:
  [4 C's / K8s security](https://kubernetes.io/docs/concepts/security/overview/) ·
  [CNCF Cloud Native Security](https://www.cncf.io/reports/cloud-native-security-whitepaper/) ·
  [OWASP Top 10](https://owasp.org/www-project-top-ten/) ·
  [NIST Zero Trust](https://csrc.nist.gov/pubs/sp/800/207/final) ·
  [SLSA](https://slsa.dev/spec/v1.0/threats).
