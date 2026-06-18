#!/usr/bin/env bash
# Offline `crossplane render` test for the Environment Composition (ADR-067 / L2a #383). Runs the Pipeline
# functions via Docker and asserts the rendered Environment footprint — no cluster. Heavier than the schema
# check (Docker + function image pulls), so it runs as its own CI job ("Environment Composition Render"), not in
# run.sh. Requires crossplane + docker. the sole API surface since the cutover (the v2 Composition was removed).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
comp="${here}/../charts/environment-api/files/composition.yaml"
fns="${here}/render/functions.yaml"
envcfg="${here}/render/environmentconfig.yaml"

command -v crossplane >/dev/null 2>&1 || { echo "::error::crossplane CLI not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "::error::docker is required for crossplane render"; exit 1; }

render() { crossplane render "$1" "$comp" "$fns" --extra-resources "$envcfg" 2>/dev/null; }

echo "== render demo-dev (first-deploy: web service, no image) → footprint + product-scoped ECR/identity =="
OUT="$(render "${here}/environments/demo-dev.yaml")"
printf '%s' "$OUT" | grep -q 'name: alpha-demo-dev$'                  || { echo "::error::namespace alpha-demo-dev not rendered"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/product: demo'     || { echo "::error::product label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/stage: dev'        || { echo "::error::stage label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: team-alpha/demo-web'     || { echo "::error::product-scoped ECR team-alpha/demo-web not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: Pod-alpha-demo-dev-web'  || { echo "::error::Pod role Pod-alpha-demo-dev-web not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: alpha-demo-dev:developers'        || { echo "::error::developer RoleBinding group wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 'team-alpha/demo-\*'                     || { echo "::error::restrict-images scope should be team-alpha/demo-*"; exit 1; }
printf '%s' "$OUT" | grep -q 'demo-alpha-dev.preprod.aws.refplat.org' || { echo "::error::generated host demo-alpha-dev not in the allow-list"; exit 1; }
echo "  ✓ demo-dev OK (ns alpha-demo-dev, ECR team-alpha/demo-web, role Pod-alpha-demo-dev-web, restrict-images team-alpha/demo-*)"

echo "== render shop-bigbank-prod (per-customer pci prod, image + permissions) → customer-ns + RolePolicy =="
OUT="$(render "${here}/environments/shop-bigbank-prod.yaml")"
printf '%s' "$OUT" | grep -q 'name: alpha-shop-bigbank-prod$'        || { echo "::error::per-customer namespace alpha-shop-bigbank-prod not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/customer: bigbank' || { echo "::error::customer label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: team-alpha/shop-api'     || { echo "::error::ECR team-alpha/shop-api not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: Pod-alpha-shop-bigbank-prod-api' || { echo "::error::per-customer Pod role Pod-alpha-shop-bigbank-prod-api not rendered (the role MUST carry the customer or two per-customer prod Environments collide on one IAM role)"; exit 1; }
printf '%s' "$OUT" | grep -q 'Customer: bigbank'                     || { echo "::error::per-customer Pod role missing the Customer tag"; exit 1; }
printf '%s' "$OUT" | grep -q 's3:GetObject'                          || { echo "::error::per-service RolePolicy missing the granted action"; exit 1; }
printf '%s' "$OUT" | grep -q 'permissionsBoundary'                   || { echo "::error::minted role missing the permissions boundary"; exit 1; }
printf '%s' "$OUT" | grep -q 'host: shop.example.com'                || { echo "::error::bound domain shop.example.com not in status.domains"; exit 1; }
printf '%s' "$OUT" | grep -q 'reason: BoundDomain'                   || { echo "::error::bound domain should be reason BoundDomain"; exit 1; }
echo "  ✓ shop-bigbank-prod OK (customer-ns, ECR team-alpha/shop-api, role Pod-alpha-shop-bigbank-prod-api + Customer tag + RolePolicy + boundary, bound domain Active)"

echo "== render resources-s3-dev (ADR-073: S3 objectstore on a service) → safe MRs + derived IAM + ConfigMap =="
OUT="$(render "${here}/environments/resources-s3-dev.yaml")"
# Bucket name is deterministic <prefix><team>-<product>-<stage>-<name>-<hash>; assert the friendly stem (the
# 8-char hash suffix varies but the stem is stable).
printf '%s' "$OUT" | grep -q 'kind: Bucket'                                  || { echo "::error::S3 Bucket MR not rendered"; printf '%s\n' "$OUT"; exit 1; }
# Resource plane is namespaced (ADR-073/#574): MRs live in the env namespace so the catalog/Backstage K8s plugin
# can read their live status. Guard the scope migration directly (the kind is the same cluster vs namespaced).
printf '%s' "$OUT" | grep -q 'apiVersion: s3.aws.m.upbound.io/v1beta1'       || { echo "::error::S3 resource MRs must be the namespaced variant (s3.aws.m.upbound.io) — #574"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/product: shop'           || { echo "::error::resource MRs must carry the product label (Backstage label-selector match) — #574"; exit 1; }
# v2 namespaced MRs have no spec.deletionPolicy; the orphan-equivalent is managementPolicies WITHOUT "Delete".
printf '%s' "$OUT" | grep -q 'managementPolicies:'                           || { echo "::error::namespaced MRs must set managementPolicies (v2 has no deletionPolicy) — #574"; exit 1; }
printf '%s' "$OUT" | grep -A5 'managementPolicies:' | grep -qx '  - Delete'  && { echo "::error::resource MRs must omit the Delete management policy (orphan-equivalent: retain AWS resource on deprovision) — #574"; exit 1; } || true
printf '%s' "$OUT" | grep -q 'external-name: refplat-alpha-shop-dev-uploads-' || { echo "::error::deterministic bucket name refplat-alpha-shop-dev-uploads-<hash> not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'kind: BucketPublicAccessBlock'                 || { echo "::error::BucketPublicAccessBlock not rendered (public-access not blocked)"; exit 1; }
printf '%s' "$OUT" | grep -q 'restrictPublicBuckets: true'                   || { echo "::error::restrictPublicBuckets must be true"; exit 1; }
printf '%s' "$OUT" | grep -q 'kind: BucketServerSideEncryptionConfiguration' || { echo "::error::SSE config not rendered (bucket unencrypted)"; exit 1; }
printf '%s' "$OUT" | grep -q 'sseAlgorithm: AES256'                          || { echo "::error::standard tier must be SSE-S3 (AES256)"; exit 1; }
printf '%s' "$OUT" | grep -q 'kind: BucketVersioning'                        || { echo "::error::BucketVersioning not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'objectOwnership: BucketOwnerEnforced'          || { echo "::error::BucketOwnershipControls BucketOwnerEnforced not rendered"; exit 1; }
# Namespaced schema (#574): the upbound .m. family collapsed these MaxItems=1 blocks from TF-style lists to single
# objects. crossplane render does NOT validate provider CRD schemas, so guard the object form here (a list form
# applies fine in render but is admission-rejected by the namespaced CRD as "expected map, got []").
printf '%s' "$OUT" | grep -qE '^[[:space:]]*- sseAlgorithm'                  && { echo "::error::applyServerSideEncryptionByDefault must be an object, not a list (namespaced s3 schema) — #574"; exit 1; } || true
printf '%s' "$OUT" | grep -qE '^[[:space:]]*- status: Enabled'               && { echo "::error::versioningConfiguration must be an object, not a list (namespaced s3 schema) — #574"; exit 1; } || true
printf '%s' "$OUT" | grep -qE '^[[:space:]]*- objectOwnership'               && { echo "::error::BucketOwnershipControls rule must be an object, not a list (namespaced s3 schema) — #574"; exit 1; } || true
printf '%s' "$OUT" | grep -q 'DenyInsecureTransport'                         || { echo "::error::BucketPolicy must deny non-TLS"; exit 1; }
# Derived least-privilege IAM: readwrite bucket gets PutObject; the ARN is scoped to the bucket (never *).
printf '%s' "$OUT" | grep -q 's3:PutObject'                                  || { echo "::error::readwrite resource must derive s3:PutObject"; exit 1; }
printf '%s' "$OUT" | grep -q 'arn:aws:s3:::refplat-alpha-shop-dev-uploads-'  || { echo "::error::derived IAM must be scoped to the bucket ARN"; exit 1; }
# read-only resource must NOT be able to write its bucket — there should be exactly one PutObject (uploads).
[ "$(printf '%s' "$OUT" | grep -c 's3:PutObject')" -eq 1 ]                    || { echo "::error::read-only 'assets' bucket must NOT derive PutObject (only readwrite 'uploads')"; exit 1; }
# Outputs ConfigMap web-resources carries both bucket names for envFrom consumption.
printf '%s' "$OUT" | grep -q 'name: web-resources'                           || { echo "::error::web-resources ConfigMap not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'UPLOADS_BUCKET:'                               || { echo "::error::UPLOADS_BUCKET output key missing from ConfigMap"; exit 1; }
printf '%s' "$OUT" | grep -q 'ASSETS_BUCKET:'                                || { echo "::error::ASSETS_BUCKET output key missing from ConfigMap"; exit 1; }
# SQS (ADR-073 A.1): a Queue, SSE-SQS on, deny-non-TLS policy, derived queue-scoped IAM, QUEUE_URL output.
printf '%s' "$OUT" | grep -q 'kind: Queue'                                   || { echo "::error::SQS Queue MR not rendered"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'apiVersion: sqs.aws.m.upbound.io/v1beta1'      || { echo "::error::SQS Queue must be the namespaced variant (sqs.aws.m.upbound.io) — #574"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: refplat-alpha-shop-dev-jobs-'            || { echo "::error::deterministic queue name refplat-alpha-shop-dev-jobs-<hash> not rendered"; exit 1; }
# SQS external-name is the queue URL; it MUST be pinned so the MR adopts an existing queue via Observe instead of
# CreateQueue (which fails QueueAlreadyExists on a tag mismatch when re-created during the cluster→ns migration) — #574.
printf '%s' "$OUT" | grep -qE 'external-name: https://sqs\.us-east-1\.amazonaws\.com/[0-9]+/refplat-alpha-shop-dev-jobs-' || { echo "::error::SQS Queue must pin crossplane.io/external-name to the queue URL (adoption) — #574"; exit 1; }
printf '%s' "$OUT" | grep -q 'sqsManagedSseEnabled: true'                    || { echo "::error::SQS queue must be SSE-SQS encrypted"; exit 1; }
printf '%s' "$OUT" | grep -q 'sqs:SendMessage'                               || { echo "::error::readwrite queue must derive sqs:SendMessage"; exit 1; }
printf '%s' "$OUT" | grep -q 'sqs:ReceiveMessage'                            || { echo "::error::queue must derive sqs:ReceiveMessage"; exit 1; }
printf '%s' "$OUT" | grep -q 'arn:aws:sqs:us-east-1:[0-9]*:refplat-alpha-shop-dev-jobs-' || { echo "::error::derived IAM must be scoped to the queue ARN"; exit 1; }
printf '%s' "$OUT" | grep -q 'JOBS_QUEUE_URL:'                               || { echo "::error::JOBS_QUEUE_URL output key missing from ConfigMap"; exit 1; }
# SNS (ADR-073 A.1): a Topic, SSE (AWS-managed key), deny-non-TLS, derived publish IAM + kms-via-service, ARN output.
printf '%s' "$OUT" | grep -q 'kind: Topic'                                   || { echo "::error::SNS Topic MR not rendered"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'apiVersion: sns.aws.m.upbound.io/v1beta1'      || { echo "::error::SNS Topic must be the namespaced variant (sns.aws.m.upbound.io) — #574"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: refplat-alpha-shop-dev-notify-' || { echo "::error::deterministic topic name (external-name) not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'kmsMasterKeyId: alias/aws/sns'                  || { echo "::error::SNS topic must be SSE (alias/aws/sns)"; exit 1; }
printf '%s' "$OUT" | grep -q 'sns:Publish'                                   || { echo "::error::readwrite topic must derive sns:Publish"; exit 1; }
printf '%s' "$OUT" | grep -q 'kms:GenerateDataKey'                           || { echo "::error::SSE publish must derive kms:GenerateDataKey (via-service scoped)"; exit 1; }
printf '%s' "$OUT" | grep -q 'sns.us-east-1.amazonaws.com'                    || { echo "::error::kms perms must be scoped to the SNS service via kms:ViaService"; exit 1; }
printf '%s' "$OUT" | grep -q 'NOTIFY_TOPIC_ARN:'                             || { echo "::error::NOTIFY_TOPIC_ARN output key missing"; exit 1; }
# DynamoDB (ADR-073 A.1): a Table, on-demand, default id key, SSE + PITR, derived item IAM, table-scoped, TABLE output.
printf '%s' "$OUT" | grep -q 'kind: Table'                                   || { echo "::error::DynamoDB Table MR not rendered"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'apiVersion: dynamodb.aws.m.upbound.io/v1beta1' || { echo "::error::DynamoDB Table must be the namespaced variant (dynamodb.aws.m.upbound.io) — #574"; exit 1; }
# Identity plane stays cluster-scoped: the Pod Role + its derived RolePolicy (the access grant) belong with the
# Role, NOT in the resource namespace. Guard that we did NOT accidentally migrate IAM to the namespaced family.
printf '%s' "$OUT" | grep -q 'apiVersion: iam.aws.upbound.io/v1beta1'        || { echo "::error::Pod Role/RolePolicy must stay cluster-scoped (iam.aws.upbound.io) — identity plane, #574"; exit 1; }
if printf '%s' "$OUT" | grep -q 'iam.aws.m.upbound.io'; then echo "::error::IAM must NOT be migrated to the namespaced family (iam.aws.m.upbound.io) — #574"; exit 1; fi
printf '%s' "$OUT" | grep -q 'external-name: refplat-alpha-shop-dev-sessions-' || { echo "::error::deterministic table name not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'billingMode: PAY_PER_REQUEST'                  || { echo "::error::DynamoDB must be on-demand (PAY_PER_REQUEST)"; exit 1; }
printf '%s' "$OUT" | grep -q 'hashKey: id'                                   || { echo "::error::DynamoDB default hashKey id not rendered"; exit 1; }
printf '%s' "$OUT" | grep -A2 'serverSideEncryption:' | grep -q 'enabled: true' || { echo "::error::DynamoDB must enable SSE"; exit 1; }
printf '%s' "$OUT" | grep -A2 'pointInTimeRecovery:' | grep -q 'enabled: true' || { echo "::error::DynamoDB must enable PITR"; exit 1; }
# Namespaced schema (#574): serverSideEncryption/pointInTimeRecovery are objects, not MaxItems=1 lists.
printf '%s' "$OUT" | grep -qE '^[[:space:]]*- enabled: true'                 && { echo "::error::DynamoDB serverSideEncryption/pointInTimeRecovery must be objects, not lists (namespaced dynamodb schema) — #574"; exit 1; } || true
printf '%s' "$OUT" | grep -q 'dynamodb:PutItem'                              || { echo "::error::readwrite table must derive dynamodb:PutItem"; exit 1; }
printf '%s' "$OUT" | grep -q 'arn:aws:dynamodb:us-east-1:[0-9]*:table/refplat-alpha-shop-dev-sessions-' || { echo "::error::derived IAM must be scoped to the table ARN"; exit 1; }
printf '%s' "$OUT" | grep -q 'SESSIONS_TABLE:'                              || { echo "::error::SESSIONS_TABLE output key missing"; exit 1; }
echo "  ✓ resources-s3-dev OK (S3 + SQS + SNS topic (SSE/TLS-only/publish+kms) + DynamoDB table (on-demand/SSE/PITR/item IAM); all engine-scoped IAM; web-resources ConfigMap)"

echo "Environment Composition render checks passed (L2a — product-scoped footprint + identity; ADR-073 — S3/SQS/SNS/DynamoDB resources)."
