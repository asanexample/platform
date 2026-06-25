# triage-copilot-identity

The AWS identity for the **triage-copilot** agent (ADR-080) — a propose-only,
read-only, on-the-loop incident-triage agent and the template platform agent
(ADR-074). Identity-only: this module provisions the IAM role + EKS Pod Identity
association; the agent **workload** (namespace, ServiceAccount, Deployment, RBAC)
is delivered by ArgoCD from the app repo, not here.

## What it grants

- An IAM role trusted by `pods.eks.amazonaws.com` (EKS Pod Identity, ADR-047).
- **Exactly one permission:** `bedrock:InvokeModel` / `InvokeModelWithResponseStream`
  on the Claude inference-profile (and the foundation-model ARNs it routes to for
  cross-region inference). Nothing else.
- A Pod Identity association binding the agent's ServiceAccount to the role.

## What it deliberately does NOT grant

Observability (Loki/Mimir/Tempo) is read over **in-cluster HTTP**; Kubernetes and
ArgoCD state are read via the in-cluster ServiceAccount **RBAC** — none of that is
IAM. There is **no write or remediation permission anywhere** in this grant: the
"never remediates" property is an IAM fact, not a prompt instruction (ADR-080 D4).

## Prerequisite

Amazon Bedrock **model access** for the Claude model must be enabled in the target
account before invoke succeeds (an account-level enablement, separate from this IAM).
