# Durable, keep-forever S3 corpus for the triage agent's forward-captured evaluation fixtures
# (ADR-080 D6 / ADR-086). The always-on production-shadow source of the eval corpus: an incident not
# captured when it happens is lost (short telemetry retention), and the accrued corpus later feeds the
# shadow→proven→promoted graduation signal that gates agent autonomy. Platform-owned durable state,
# deliberately NOT tied to any agent version. Cloud-only unit (no cluster dependency). The agent's WRITE
# grant is identity-based, declared in gitops/agents/triage-copilot.yaml (awsPermissions.policyStatements).

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.agent_eval_store
}

inputs = {
  create = true

  # Deterministic so the ARN is known at agent-claim-authoring time for the identity-based write grant.
  bucket_name = "platform-agent-eval-corpus"

  # Encryption follows the cost profile (ADR-092 shift-left FinOps): dev/cost → SSE-S3 (no dedicated-key cost,
  # matching the LGTM buckets); prod/regulated → a dedicated CMK (key-level access control + audit) for this
  # sensitive, kept-forever, LLM-replayed corpus. Flip via cost_profile (common.hcl) or an explicit
  # high_availability override. Metadata-first capture is the primary data control in either mode.
  use_kms_cmk = include.base.locals.high_availability

  # No cross-account CI replay/grader role exists yet (ADR-080 D6 follow-up in the app repo); the read
  # seam stays empty until it does. Object Lock / WORM likewise deferred to the graduation slice.

  tags = include.base.locals.tags
}
