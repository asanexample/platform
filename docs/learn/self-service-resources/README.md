# Learn: Self-Service Cloud Resources

How a developer gets a real S3 bucket, SQS queue, SNS topic, or DynamoDB table — no ticket, no waiting, and
**no writing IAM** — handed over least-privilege and safe-by-construction every time. This is the resource
paved road.

Written for developers: this is your self-service. Platform engineers who want the Composition internals get
those at the end of the orientation. It builds on the [Environment API](../environment-api/) — these resources
are a field on your claim — so read the [Environment API orientation](../environment-api/orientation.md) (the
`XEnvironment` claim) first, and ideally [Identity & Access](../identity/orientation.md) for Pod Identity.

## Read in this order

1. **[Orientation](orientation.md)** — one idea, *abstraction above the claim, safety below*, taught on a real
   service (`acme/conformance` — four resources from four lines, running in steady state): abstract intent
   (`kind`/`engine`/`access`), the derived least-privilege IAM you never write, the non-overridable safety
   floor, and how the coordinates reach your app.
2. **[Reference](reference.md)** — the claim schema, the per-engine IAM tables, the safety floor, the naming,
   and the gotchas (`access` gates verbs; namespaced MRs hide from `get managed`).

**Platform engineers — the producer side:** **[Extending: add a new resource engine](extending-add-an-engine.md)**
covers adding a new engine (RDS, ElastiCache, …) to the catalog — the real touch-points and the gotchas from
building the existing four. Using a resource is easy; extending the catalog is the higher-value skill.

## Then, to go deeper

- The claim this extends: [The Environment API](../environment-api/orientation.md); where the derived IAM
  lands: [Identity & Access](../identity/orientation.md).
- Why it's shaped this way: [ADR-073 Self-Service Cloud Resources](../../adrs/073-self-service-cloud-resources.md).
- Provision one: the `environment-onboarding` skill.
