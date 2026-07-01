# agent-eval-store

Durable, keep-forever S3 corpus for the platform agents' **forward-captured evaluation fixtures**
(ADR-080 D6, ADR-086). Each captured case — `{alert-group, telemetry snapshot, structured label, rubric}`
plus `results/` records — is written write-once by the agent at triage time and its label back-fills later.
This corpus is the always-on `production-shadow` source of the eval corpus and, once it accrues, the input to
the `shadow → proven → promoted` graduation signal that gates agent autonomy.

## Why this bucket is hardened beyond the other buckets

Unlike the LGTM / cost-export buckets (deliberately SSE-S3), this store holds **potentially-sensitive
telemetry forever** *and* is later replayed into an LLM (Bedrock). It is therefore the "regulated-tier
upgrade" those modules defer to:

- **SSE-KMS with a dedicated CMK** (`alias/<bucket_name>`) — key-level access control + CloudTrail audit +
  revocable-by-key-policy.
- **TLS-only** bucket policy; full public-access block; `BucketOwnerEnforced`.
- **Versioning on**; the writer (agent) is granted `PutObject`/`GetObject` but **no `DeleteObject`** (corpus
  integrity). S3 Object Lock / WORM is a seam (`object_lock_enabled`, default off), adopted in the graduation
  slice when the corpus actually gates power.

## Data-classification contract (metadata-first)

Producers (the agent app) MUST capture **structured values + bounded context** (metric samples, event
reasons, the taxonomy label) — **not raw unredacted log/trace content** — until ADR-076's
content-capture-with-redaction lands. Raw-content capture is a deferred, gated upgrade. This bucket provides
the technical controls (encryption, no-public, TLS-only); the redaction posture is the producer's data control.

## Access model

- **Write:** identity-based on the agent's Composition-minted Pod-Identity role, declared in its `XAgent`
  claim's `awsPermissions.policyStatements` (`s3:PutObject`/`GetObject` on `<bucket>/*`, `kms:GenerateDataKey`/
  `Encrypt`/`Decrypt` on the CMK). Not granted here, to avoid a chicken-and-egg on the runtime role ARN.
- **Read (future):** `reader_role_arns` adds a resource-based read grant (S3 + KMS Decrypt) for a later
  cross-account CI replay/grader role (ADR-080 D6). Default empty — no such role exists yet.

## Key variables

| Variable | Default | Purpose |
|---|---|---|
| `bucket_name` | — | Deterministic name (e.g. `platform-agent-eval-corpus`) so the ARN is known at claim-authoring time |
| `object_lock_enabled` | `false` | WORM seam (graduation slice) — forces replacement, set at creation |
| `reader_role_arns` | `[]` | Future cross-account CI read grant (S3 + KMS Decrypt) |
| `transition_to_ia_days` | `0` | Optional aged-fixture tiering to Standard-IA; 0 = off |
| `force_destroy` | `false` | Keep false for the durable corpus; test fixtures may set true |

## Outputs

`bucket_name`, `bucket_arn`, `kms_key_arn`, `kms_key_alias`.

## Testing

Terratest (Go) under `infra/tests/aws/agent-eval-store/` with `TerraformBinary: "tofu"` — asserts
public-access-block, SSE-KMS, versioning, and the TLS-only/no-public bucket policy.
