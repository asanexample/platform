# Learn: Secrets & Config

How the platform handles secrets and config: by *not having* long-lived secrets wherever it can (federation),
and keeping the irreducible few on two clean planes — **config-in-git** (SOPS) and **runtime secrets**
(External Secrets Operator + AWS Secrets Manager).

**Audience:** platform engineers, and any developer wondering where a password actually comes from.
**Before you start:** [Identity & access](../identity/orientation.md) (federation eliminates most secrets) and
[Foundations → IaC](../foundations/deep-dive-infrastructure-as-code.md) (the Terragrunt config chain) help.

## Read in this order

1. **[Orientation](orientation.md)** — *"the best secret is one that doesn't exist."* The one idea (eliminate →
   seal in git → vault + sync), the two-planes model, and a tour through config, runtime secrets, and rotation,
   with an honest live-vs-designed status. Metaphor: keys to a building.
2. **[Reference](reference.md)** — the dense lookup: the two planes, the SOPS mechanism, the ESO
   ClusterSecretStore/ExternalSecret pattern, the tenant paved road, the rotation classification, the status
   ledger, gotchas.

## Go deep

- **[Config in git (SOPS)](deep-dive-config-in-git.md)** — the SOPS/KMS mechanism, the `platform-sops`
  key-policy-as-ACL, the `TG_SOPS_BOOTSTRAP` escape, and where the boundary between SOPS and ESO falls.
- **[Runtime secrets (ESO + Secrets Manager)](deep-dive-runtime-secrets.md)** — the ClusterSecretStore +
  ExternalSecret mechanism, a live worked example, naming/scoping, keyless-first, and the *designed* tenant
  self-service road (ADR-070).
- **[Rotation & lifecycle](deep-dive-rotation.md)** — the four-class classification, the three primitives
  (Reloader / age-alerts / refresh-tiers), the one-owner guardrail, the deliberate not-Vault, and the honest
  built-vs-designed status (ADR-094, mostly design).

## Then

- How federation eliminates secrets: [Identity & access](../identity/orientation.md). Where the config chain
  reads them: [Foundations → IaC](../foundations/deep-dive-infrastructure-as-code.md). Manual break-glass:
  the `docs/runbooks/secret-rotation.md` runbook.
