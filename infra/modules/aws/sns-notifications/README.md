# sns-notifications

Creates an **SNS topic** for platform alert notifications — the fan-out target for the observability
Alertmanager (critical alerts) and Falco's falcosidekick (runtime security events) — plus optional email
subscriptions. Minimal by design: publishers are granted `sns:Publish` via **their own** IAM identity policy on
the topic ARN, kept off the topic resource policy so this module does **not** depend on those roles (avoids a
dependency cycle; same-account publish works on the default topic policy).

## What it deploys

- An **`aws_sns_topic`** (default name `platform-alerts`), SSE-KMS encrypted at rest. Defaults to the
  AWS-managed SNS key (`alias/aws/sns`); a customer-managed CMK upgrade is tracked in #118. Publishers must hold
  `kms:GenerateDataKey*` / `kms:Decrypt` on the key (the Alertmanager IRSA role does).
- One **email subscription** per address in `alert_emails`. Each subscription must be **confirmed** via the
  email AWS sends before notifications flow.

## Key inputs

- `topic_name` (default `platform-alerts`).
- `alert_emails` — list of subscriber email addresses (default `[]`).
- `kms_master_key_id` (default `alias/aws/sns`).
- `create`, `tags`.

## Outputs

- `topic_arn` — publishers grant themselves `sns:Publish` on this via their own IAM identity policy.
- `topic_name`.

## Dependencies

None. Publishers (Alertmanager IRSA, falcosidekick) reference `topic_arn` and self-grant publish, so this module
has no upstream dependency on those identities.

## Related

- Issue #118: customer-managed CMK upgrade for SNS/CloudTrail/state-bucket encryption
