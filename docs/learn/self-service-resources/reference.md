# Learn: Self-Service Cloud Resources — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first.

## The claim

A field on your [Environment claim](../environment-api/orientation.md), under each service:

```yaml
services:
  <service>:
    serviceAccount: <sa-name>
    resources:
      <name>:                 # your logical name → becomes env var + resource suffix
        kind: <class>         # objectstore | stream | keyvalue | (schema: relational | cache)
        engine: <impl>        # s3 | sqs | sns | dynamodb
        access: read | readwrite
```

- **`kind`** is the abstract class; **`engine`** the concrete implementation; **`access`** your intent.
- **Built + live today:** `s3` (objectstore), `sqs` + `sns` (stream), `dynamodb` (keyvalue) — all four
  provisioned & ready on preprod (`alpha/conformance/dev`). *(The XRD carries a stale `Phase A: objectstore/s3`
  comment — all four engines actually ship; see #drift below.)*

## Derived least-privilege IAM (per engine)

Generated from `access`, scoped to **that one resource's ARN**, appended to the service's **Pod-Identity
`RolePolicy`**. You never author it.

| engine | `read` | `readwrite` adds |
| --- | --- | --- |
| **s3** | `GetObject`, `ListBucket`, `GetBucketLocation` | `PutObject`, `DeleteObject`, `AbortMultipartUpload` |
| **sqs** | `ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility`, `GetQueueAttributes`, `GetQueueUrl` | `SendMessage` |
| **sns** | `GetTopicAttributes`, `Subscribe`, `ListSubscriptionsByTopic` | `Publish` |
| **dynamodb** | `GetItem`, `BatchGetItem`, `Query`, `Scan`, `DescribeTable`, `ConditionCheckItem` | `PutItem`, `UpdateItem`, `DeleteItem`, `BatchWriteItem` |

## The safety floor (below the claim, non-overridable)

- **S3:** PublicAccessBlock, **TLS-only** (`DenyInsecureTransport` bucket policy), Versioning,
  OwnershipControls, region-pinned, encrypted.
- **All engines:** encrypted + `DenyInsecureTransport`. **Encryption tiered:** `standard` → service-managed
  (SSE-S3 / SSE-SQS / DynamoDB default, zero key ops); `elevated`/`pci`/`hipaa` → **per-team KMS CMK**
  (cryptographic tenancy isolation, key policy scoped to the team's roles).

## Consumption

A **`<service>-resources` ConfigMap** injects the real coordinates as env vars — read these, never hardcode:

```text
BLOB_BUCKET · JOBS_QUEUE_URL · EVENTS_TOPIC_ARN · SESSIONS_TABLE   (⇒ <NAME>_<SUFFIX> per resource)
```

Naming: `refplat-<team>-<product>-<stage>-<name>-<hash>` (deterministic, ≤63-char safe, collision-resistant).

## Front doors (above the claim)

All produce the same governed claim → same validation → same realization. **Built:** PR-as-code, Backstage
form. **Designed (ADR-073 Phase B):** a natural-language agent. New front doors never touch the safety floor.

## Gotchas that teach

- **`access` gates the verbs.** `read` can't write — no `PutObject`/`SendMessage`/`Publish`. Bump to
  `readwrite`.
- **The IAM lands on the *named* ServiceAccount's Pod-Identity role.** A pod under a different SA won't have
  it. Match `serviceAccount`.
- **The resources are *namespaced* MRs** (`s3.aws.m.upbound.io`, Crossplane v2) — cluster-scoped
  `kubectl get managed` **won't list them**; use `kubectl -n <env-ns> get bucket.s3.aws.m.upbound.io …`.
- **The floor is non-overridable** — no public access, no non-TLS, no disabling encryption. By design.
- <a id="drift"></a>**Doc drift:** the XRD's `Phase A: objectstore/s3` comment predates the sqs/sns/dynamodb
  rollout — all four engines are live. Flagged for a one-line fix.

## Glossary

- **claim** — your `XEnvironment`; `resources:` is a field on each service.
- **kind / engine / access** — abstract class / concrete impl / intent (read vs readwrite).
- **derived IAM** — the least-privilege policy the platform computes from `access`, scoped to the ARN.
- **safe-by-construction** — hardening applied below the claim that you can't configure or disable.
- **managed resource (MR)** — the Crossplane object representing the real AWS resource.

## Go deeper

- [ADR-073 Self-Service Cloud Resources](../../adrs/073-self-service-cloud-resources.md) · the
  [Environment API](../environment-api/orientation.md) (the claim) · [Identity & Access](../identity/orientation.md)
  (where the IAM lands).
- Substrate: [Crossplane](https://docs.crossplane.io/latest/) ·
  [Upbound AWS provider](https://marketplace.upbound.io/providers/upbound/provider-family-aws) ·
  [AWS IAM least-privilege](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege).
