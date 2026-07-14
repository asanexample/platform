# Learn: Supply Chain — reference

Definitions, commands, and gotchas to look up. The [orientation](orientation.md) walks through how the pieces fit.

## The pipeline (produce the trustworthy artifact)

One shared, reusable workflow the platform owns (`asanexample/trusted-ci/build-sign.yml`) does the whole
backbone; each app's CI is a thin caller:

```text
build → push to ECR → cosign sign (keyless) → SLSA provenance (isolated) → SBOM
```

- **Keyless signing** — [cosign](https://docs.sigstore.dev/cosign/signing/overview/) / Sigstore: the CI's
  GitHub Actions OIDC identity → Fulcio issues a short-lived cert → sign → logged in Rekor
  (public transparency log). No private key exists.
- **SLSA Build L3 provenance** — generated in an isolated workflow the app team can't write, so the build
  can't forge its own.
- **SBOM** — the image's ingredient list (vuln queryability).

## Inspect it yourself (real commands)

```console
$ cosign tree <platform-acct>.dkr.ecr.us-east-1.amazonaws.com/team-acme/shop-web@sha256:f6b37d…
└── 🔐 Signatures …          # 1 signature
└── 💾 Attestations …        # 2: SLSA provenance (v0.2) + CycloneDX SBOM

$ cosign verify … team-acme/shop-web@sha256:f6b37d…
Issuer:  https://token.actions.githubusercontent.com          # keyless (GitHub Actions OIDC)
Subject: …/asanexample/trusted-ci/…/build-sign.yml@…          # the shared signer
githubWorkflowRepository: asanexample/acme-shop              # the caller repo = the trust anchor
```

## The trust rule

An image is trusted iff its signing cert's `githubWorkflowRepository` equals the Product's declared
`spec.repo` (Product registry). Per-product and registry-derived, not "any signed image." A validly-signed
image from the wrong repo is rejected.

## Verify at admission (the enforce half)

Kyverno fetches signature + attestations from ECR (via Pod Identity ECR-read) and enforces, per product:

- `verify-images-product-<team>-<product>` — signed by the shared workflow, cert repo = the product's repo.
- `verify-attestations-product-<team>-<product>` — SLSA provenance + SBOM present.

Both Enforce on preprod — unsigned, unattested, or wrong-repo images never admit. (Platform-owned; the
[Policy & Admission](../policy/orientation.md) module covers the admission mechanics. Per-product image
registry scoping is separate — owned by the Environment Composition.)

## Gotchas

- **Signed ≠ safe.** Signing and provenance prove origin and integrity, not that the code is free of bugs
  or poisoned deps — a compromised upstream dependency is legitimately signed.
  [SLSA's threat model](https://slsa.dev/spec/v1.0/threats) is explicit: it covers build tampering, not a
  malicious author. Layer SBOM-driven vulnerability scanning on top; signing is necessary, not sufficient.
- **Repo rename breaks trust.** Trust is keyed on the repo in the cert; renaming a Product's repo without
  updating `spec.repo` makes every new image fail verification. Update the registry with the rename.
- **Signature and attestation are separate policies.** An image can be signed but missing attestations (or
  vice versa) — both must pass. `cosign tree` shows what's actually attached.
- **Isolation is the point of L3.** Provenance the build could edit is L2 at best. The isolated
  `trusted-ci` workflow (app-team-unwritable) is what makes it L3 — don't inline it back into the app
  repo.

## Glossary

- **cosign / Sigstore** — the keyless signing toolchain (Fulcio CA + Rekor transparency log).
- **keyless** — signing with a short-lived OIDC identity + momentary cert instead of a stored private key.
- **SLSA provenance** — a signed statement of *how/where/from-what-commit* an artifact was built.
- **SBOM** — Software Bill of Materials; the image's dependency inventory.
- **attestation** — a signed claim *about* an artifact (provenance and SBOM are attestations).
- **thin caller** — an app CI that invokes the shared signing workflow rather than implementing signing.

## Go deeper

- Onboard an app: the `supply-chain-onboarding` skill. Enforce side:
  [Policy & Admission](../policy/orientation.md).
- Substrate & explainers: [cosign](https://docs.sigstore.dev/cosign/signing/overview/) ·
  [Sigstore's trust model](https://docs.sigstore.dev/about/security/) ·
  [Rekor transparency log](https://docs.sigstore.dev/logging/overview/) ·
  [SLSA levels](https://slsa.dev/spec/v1.0/levels) + [threat model](https://slsa.dev/spec/v1.0/threats)
  ([gentle intro](https://edu.chainguard.dev/compliance/slsa/what-is-slsa/)) ·
  [in-toto](https://in-toto.io/) · [CycloneDX SBOM](https://cyclonedx.org/specification/overview/).
