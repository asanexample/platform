# How-to: onboard a new Team (a playbook)

A playbook for putting a new **Team** on the platform. A Team is the top-level governance object — it
carries a team's *identity* (the SSO group it maps to) and its *envelope* (the bound on everything the
team's Products and Environments may ever ask for). By the end, one small file in git has become a GitHub
org team, a Keycloak group, and an admission-enforced boundary the whole platform reads.

This is the procedure. For *why* a Team is an envelope and how admission checks it, read
[the domain model](../domain-model/orientation.md#the-team-is-an-envelope) first — that walks the concept
and the four-request admission story, and this doc doesn't repeat them. For how the SSO group becomes
sign-in and roles, see [identity](../identity/orientation.md). Here you just get it built.

> Working with an AI agent? Authoring a Team file is a good agent task — the risk is the *envelope*, not
> the YAML. See [Doing this with an agent](#doing-this-with-an-ai-agent) for a prompt, guardrails, and a
> review checklist. Come back here to review its PR.

## Before you start

- **This is admin-only work.** A Team grants an *envelope*, so onboarding one is a platform-admin
  decision, not team self-service (developers author Products and Environments *inside* an existing Team,
  not the Team itself). Both paths below are gated so only an admin can land one.
- **A name.** `metadata.name` is a bare lowercase slug, `^[a-z][a-z0-9]{1,15}$` — letters and digits, **no
  hyphens**. The team name is parsed back out of `<team>-<product>-<stage>` namespace names, so a hyphen
  would make that split ambiguous. `alpha`, not `a-l-p-h-a`. (The Backstage form enforces exactly this pattern;
  the Teams Gate's own regex is looser — it permits hyphens and longer names — so on a hand-authored Path B
  PR the reviewer, not the gate, is what catches a stray hyphen.)
- **An SSO group.** The upstream group this Team maps to (`spec.ssoGroup`). The convention is `Dev-<name>`
  (so `Dev-alpha`); a tenant Team may **not** map to a privileged/platform group. The Teams Gate rejects the
  *configured* denied set (today just `platform-admins`, matched case-insensitively) — note `Platform` itself
  is **not** in that set (the platform-owned Team uses it), so CODEOWNERS review, not the gate, is the
  backstop for every other privileged group.
- **An envelope.** The tiers, stages, quota ceiling, budget, and self-service limits every Environment
  under this Team is bounded by. Copy an existing Team and adjust; the fields are in the
  [table below](#the-envelope-field-by-field).

## What you're actually doing

You're making a [GitOps](https://opengitops.dev/) change: git is the source of truth, and the platform
reconciles reality to match it. The Team registry (`gitops/teams/**`) is the single list of every team,
and adding one file onboards a team. Several platform units and a Kyverno policy *derive* from that file —
you provision none of it by hand. Your whole job is to write one good file and open a PR.

---

## Path A — the Backstage scaffolder

The paved path is the New Team
[software template](https://backstage.io/docs/features/software-templates/):

1. In Backstage, **Create → New Team**.
2. Fill the form: **name**, **ssoGroup** (optional; defaults to `Dev-<name>`), and the envelope fields
   (`allowedTiers`, stages, `cpu`, `memory`, `pods`).
3. The template runs a server-side **admin check** (`requireAdmin`) — since team members can create
   scaffolder tasks for *self-service* templates, this one restricts *running it* to platform admins. It
   then writes `gitops/teams/<name>.yaml` and opens a PR (`team/onboard-<name>`) against `main`. It
   **opens a PR — it never automerges.** A Team grants an envelope, so it always gets human review.
4. Review and merge that PR → [What happens on merge](#what-happens-on-merge).

> ⚠️ **The scaffolder skeleton is currently stale against the live Team schema.** It emits an older shape —
> `apiVersion: …/v1alpha2`, `envelope.allowedEnvironments`, `maxDedicatedZones` — while live Team CRs use
> `…/v1beta1`, `envelope.allowedStages`, and `maxDedicatedIsolation`, and never emit `slack`, `budget`, or
> `resources`. Until the template is refreshed, treat its output as a starting point you must reconcile
> against a real Team file before merging — or just use Path B, which is the canonical shape. This is a
> known drift, flagged in [Gotchas](#gotchas).

## Path B — a direct registry PR (the canonical shape)

Identical outcome, and the shape you can trust: hand-author the Team file and open a PR. Copy an existing
Team — an existing tenant Team is the model — and adjust.

### Step 1 — write the registry file

Add `gitops/teams/<name>.yaml`. Here's a complete, annotated example for a new team `alpha`:

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Team
metadata:
  name: alpha                      # bare slug, no hyphens; ^[a-z][a-z0-9]{1,15}$
  labels:
    app.kubernetes.io/managed-by: argocd
    app.kubernetes.io/part-of: environment-api
spec:
  ssoGroup: Dev-alpha              # the Keycloak/IdP group this team maps to (identity)
  slack:
    channel: "C0XXXXXXXXX"         # incident channel id — the triage agent posts here
  envelope:                        # the bound on every Product/Environment this team may author
    allowedTiers: ["standard"]     # compliance tiers an Environment may request
    allowedStages: ["dev", "test", "staging", "prod"]  # stages it may deploy to
    allowedLocations: ["*"]        # data-residency regions ("*" = any)
    quotaCap:                      # per-Environment ResourceQuota ceiling
      cpu: "8"
      memory: 16Gi
      pods: 40
    budget:
      monthlyUSD: 2000             # cost guardrail (surfaced/alerted, not hard-enforced)
    maxDedicatedIsolation: { cluster: 0, account: 0 }  # dedicated-isolation rungs allowed (0 = pooled only)
    resources:                     # self-service cloud resources (default-deny)
      allowedEngines: ["s3", "sqs"]  # engines the team may declare; [] = none
      maxPerEnvironment: 10        # cap on self-service resources per Environment
      isolationFloor: shared       # lowest data-isolation rung requestable
```

`spec.ssoGroup` and `spec.envelope` are the only **required** members of `spec`; within the envelope,
`allowedTiers`, `allowedStages`, and `quotaCap` are required. Everything else has a safe default (the
`resources` block defaults to **deny-all** — no engines, `maxPerEnvironment: 0` — so a team that never
opts in gets no self-service resources).

### The envelope, field by field

Each envelope field is a ceiling on what an `XEnvironment` claim under this Team may ask for. This is the
bound; [the domain model](../domain-model/orientation.md#the-team-is-an-envelope) is the concept.

| Field | What it bounds downstream | Notes |
| --- | --- | --- |
| `allowedTiers` | Environment's `spec.tier` must be in this set | enum `standard\|elevated\|pci\|hipaa`; ≥1 |
| `allowedStages` | Environment's `spec.stage` must be in this set | enum `dev\|test\|uat\|staging\|prod`; ≥1 |
| `allowedLocations` | Environment's residency must be a subset of this | default `["*"]` (any region) |
| `quotaCap.{cpu,memory,pods}` | Each Environment's `spec.quota` dimension ≤ this | an absent dimension is effectively unlimited |
| `budget.monthlyUSD` | Cost guardrail — surfaced and alerted on | **not** hard-enforced by the provisioner; absent ⇒ unbounded |
| `maxDedicatedIsolation.{cluster,account}` | How many Environments may dial the expensive isolation rungs | `0` = pooled namespace/nodes only |
| `maxCrossTeamGrantsPerProduct` | Cap on active inbound cross-team access grants per Product | default `10` |
| `resources.allowedEngines` | Self-service engines a Service may declare | enum `s3\|sqs\|sns\|dynamodb`; default `[]` (deny) |
| `resources.maxPerEnvironment` | Total self-service resources per Environment | default `0` |
| `resources.isolationFloor` | Lowest data-isolation rung requestable | `shared\|dedicated`; default `shared` |

The non-envelope fields are identity and routing, not bounds: `spec.slack.channel` is the incident channel
the triage agent posts to, and `spec.pagerduty` / `spec.oncall` point at on-call. A **platform-owned** Team
may also carry `spec.platformTrust` (cluster-read ClusterRoles + IAM actions past the deny-set) — a
capability tenants can't request. It's defined in the Team CRD but **unused by any live Team**: platform
agents get their cluster-read/model access directly from the XAgent runtime, not from a Team's
`platformTrust`. Leave it unset for a tenant Team.

> The Team **CRD does not bound** `quotaCap`, `maxDedicatedIsolation`, or `ssoGroup` — nothing in the
> schema stops you writing `cpu: "9999"`. The **Teams Gate** (below) is what enforces platform maximums and
> the privileged-group denial. That's deliberate: the envelope is the ceiling for tenants, and the gate is
> the ceiling for the envelope.

### Step 2 — open the PR

Open a pull request with just that one file. The **Teams Gate** (the required "Teams Approval" check)
validates it before merge: required fields present, enums valid, `ssoGroup` not a denied platform group,
and each cap under the platform maximum (`quotaCap`, `maxDedicatedIsolation`, `maxPerEnvironment`). It also
runs a **deletion guard** — you can't remove a Team while any Environment still references it. Fix
anything it flags; it runs *before* merge, so mistakes never reach the cluster.

<a id="what-happens-on-merge"></a>

## What happens on merge

You don't run `terragrunt apply`. Merging to `main` under `gitops/teams/**` fires `teams-apply.yml`, which
converges the derived units on the in-VPC runner, in order: **keycloak-config → argocd → argocd-apps →
github-teams**. Out of that one file come:

- **A Keycloak group** — one group per Team (`spec.ssoGroup`, e.g. `Dev-alpha`), the team's SSO identity
  that apps read from the `groups` claim.
- **A GitHub org team** — `github-teams` creates the org team (named for the slug) and later grants it
  `push` on each of the team's `<team>-<product>` repos. This is **human ownership only** — org-team
  membership is *not* in the Actions OIDC token, so it never carries supply-chain identity (that anchors on
  repo name).
- **A projected cluster `Team` CR** — ArgoCD's `teams` Application syncs the file into `crossplane-system`
  (at an early sync-wave, so Teams land *before* the environments that reference them). This is the copy
  **Kyverno** reads at `XEnvironment` admission to enforce the envelope.

The precise boundary worth holding: a **Team** materializes *identity, ownership, and the governance
envelope* — a Keycloak group, a GitHub org team, and the admission-enforced bound. The per-Product
machinery (ECR repos, the CI push role, the cosign verify policies, per-Service IAM) is derived from the
**Product** registry, keyed on `<team>-<product>` — the `<team>` there is a coordinate, not a per-Team
fan-out. Onboarding a Team builds none of that; onboarding a Product does.

## Verify it worked

- **The file is on `main`** and `teams-apply.yml` succeeded (check the Actions run).
- **The projected Team CR exists:** `kubectl --context preprod get teams` lists your team with its SSO
  group and stages.
- **The Keycloak group exists:** the `Dev-<name>` group is present in the realm.
- **The GitHub org team exists:** a team named for your slug appears in the org (it gains repo `push`
  grants as the team's Products are onboarded).
- **Admission accepts a claim:** an `XEnvironment` claim under the new Team, within its envelope, passes
  `restrict-environment-envelope` at the gitops gate.

## Doing this with an AI agent

Authoring a Team file is mechanical and well-specified — a good agent task. The risk isn't the YAML; it's
the *envelope*. An over-wide envelope (a tenant granted `pci`, or a `quotaCap` above the platform max) is a
governance hole, and a privileged `ssoGroup` is a privilege-escalation. Those are exactly what the agent
must not get wrong — and what a human must check.

**Context to attach:** this playbook, `gitops/teams/` (an existing tenant Team as the example), and the
[envelope table](#the-envelope-field-by-field).

**A starting prompt:**

> Onboard a new Team `alpha` mapping to SSO group `Dev-alpha`, following
> `docs/learn/teams/how-to-onboard-a-team.md`. Create `gitops/teams/alpha.yaml` in the **v1beta1** shape,
> copying an existing tenant Team's conventions. Envelope: `allowedTiers: ["standard"]`, stages
> `["dev","test","staging","prod"]`, `quotaCap` cpu `"8"` / memory `16Gi` / pods `40`, `budget.monthlyUSD:
> 2000`, `maxDedicatedIsolation: { cluster: 0, account: 0 }`, `resources.allowedEngines: ["s3"]`,
> `maxPerEnvironment: 10`. Open a PR with **only** that one file. Do not touch any derived infra (Keycloak,
> GitHub teams, ArgoCD, IAM) — those reconcile automatically on merge.

**Guardrails to give it:**

- **Never widen the envelope beyond what I specified.** No tier, stage, engine, or quota I didn't ask for.
  When unsure, ask — don't guess generously.
- **`ssoGroup` is the given value, never `platform`/`platform-admins`** or any privileged group. A tenant
  Team mapping to a platform group is a privilege escalation. The gate rejects only its configured denied set
  (today `platform-admins`) — don't rely on it to catch every privileged group; that's what review is for.
- **`metadata.name` is a bare slug** matching `^[a-z][a-z0-9]{1,15}$` — no hyphens.
- **Use the v1beta1 shape** (`allowedStages`, `maxDedicatedIsolation`) — *not* the scaffolder's stale
  `v1alpha2` / `allowedEnvironments` / `maxDedicatedZones`.
- **One file, no derived infra.** The agent authors *only* the registry entry; it must not hand-write the
  Keycloak group, GitHub team, or any IAM. That defeats the single-source-of-truth model and will drift.

**Review checklist:**

- [ ] `metadata.name` is a bare slug (no hyphens), `apiVersion` is `…/v1beta1`.
- [ ] `ssoGroup` is the intended group and is **not** privileged/platform.
- [ ] Every envelope value matches what you authorized — tiers, stages, quota, engines — nothing wider.
- [ ] Each cap is under the platform maximum (the Teams Gate will confirm, but check before you ask).
- [ ] PR touches *only* `gitops/teams/<name>.yaml` — no derived infra edited.
- [ ] The Teams Gate ("Teams Approval") passes.

## Gotchas

- **Admin-gated, always human-reviewed.** There is no automerge arm for Teams — an envelope grant gets a
  human, by design. Expect to (or need an admin to) approve the head SHA.
- **The scaffolder skeleton is stale.** Path A emits `v1alpha2` / `allowedEnvironments` / `maxDedicatedZones`;
  live Teams are `v1beta1` / `allowedStages` / `maxDedicatedIsolation` and carry `slack` / `budget` /
  `resources` the skeleton never writes. Prefer Path B, or reconcile the scaffolder's output against a real
  Team before merging.
- **`allowedStages` vs `allowedEnvironments` — a live wiring gap.** The keycloak-config module still derives
  its stage-based developer-access roles from the *old* `envelope.allowedEnvironments` key (with a
  `try(…, [])` fallback). Since live Teams name that field `allowedStages`, that derivation silently
  degrades to empty — the team gets its Keycloak *group*, but not the stage-derived roles. Treat the group
  as the reliable output today; flag this if you need the roles.
- **Per-team kubectl access is designed, not built.** The Keycloak group→role mapping exists, but the
  per-team `DeveloperAccess-<team>` IAM role + EKS access entry that would turn it into namespace-scoped
  kubectl is **not provisioned** — the Composition emits only the in-cluster RoleBinding. Use
  `platctl kubeconfig` / PlatformAdmin until it's built. See [identity](../identity/orientation.md).
- **You can't delete a Team that's still in use.** The Teams Gate's deletion guard rejects removing a Team
  while any Environment references it. Decommission the Environments first.
- **The `resources` block is deny-by-default.** Omit it and the team can request *no* self-service cloud
  resources. Opt in explicitly (`allowedEngines`, `maxPerEnvironment`) if the team needs S3/SQS/etc.

## Go deeper

- The concept: [the domain model — Team as envelope](../domain-model/orientation.md#the-team-is-an-envelope) ·
  identity and the SSO group: [identity](../identity/orientation.md).
- Onboarding what lives *under* a Team: [onboard a Product](../products/how-to-onboard-a-product.md).
- Substrate: [GitOps principles](https://opengitops.dev/) ·
  [Backstage software templates](https://backstage.io/docs/features/software-templates/).
