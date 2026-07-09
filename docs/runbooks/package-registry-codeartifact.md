# Package Registry (AWS CodeArtifact)

How to consume and publish **private language packages** (npm / PyPI / Maven / NuGet) on the platform, and how
public-dependency caching works. This is the package counterpart to ECR (which holds container images). See
[ADR-098](../adrs/098-package-registry-codeartifact.md) for the decision and rationale. Not covered here: Go
modules — CodeArtifact does not serve them (ADR-098 D5); use a Go module proxy or direct `GOPROXY`.

## The shape

- One CodeArtifact **domain**, `refplat`, in the **platform** account (same account as the ECR registry).
- Per-Product **consumer repositories**, named `<team>-<product>` (e.g. `alpha-shop`) — your Product's private
  packages live here, and public dependencies are pulled through and cached.
- Shared **store repositories** (`npm-store`, `pypi-store`, `maven-store`, `nuget-store`) proxy the public
  sources (npmjs, PyPI, Maven Central, NuGet Gallery). They are **upstreams** of every consumer repo, so a public
  package is fetched once and served from the domain afterwards — builds don't depend on public-registry uptime
  or rate limits.

## Auth model — no passwords, no logins to manage

CodeArtifact auth is **AWS IAM**, not a local user directory. You get a short-lived (≤12h) token from AWS
credentials you already have:

- **CI** (the usual case): your Product's GitHub Actions OIDC role
  (`github-actions-ecr-push-product-<team>-<product>`) already has **publish + read** on `refplat/<team>-<product>`
  (ADR-098 #1253) — no secret to add.
- **In-cluster workloads**: every service's Pod-Identity role has **baseline read** on its Product's repo, so a
  running pod can pull packages with ambient credentials (set `AWS_REGION` — IMDS is egress-blocked in
  environment namespaces).
- **Locally**: your own AWS SSO/role credentials, scoped by your access.

The `<platform-acct>` domain owner below is the platform account ID (the same account as your ECR registry host);
`aws codeartifact` fills it in for you when you pass `--domain-owner`, or resolve it once with
`aws sts get-caller-identity` from the platform account.

## Consume (per tool)

Region is `us-east-1`, domain `refplat`, repository `<team>-<product>`.

### npm / yarn / pnpm

```bash
aws codeartifact login --tool npm --region us-east-1 \
  --domain refplat --domain-owner <platform-acct> --repository <team>-<product>
# writes an authenticated registry + token into ~/.npmrc (valid ≤12h); then `npm install` as usual
```

### pip

```bash
aws codeartifact login --tool pip --region us-east-1 \
  --domain refplat --domain-owner <platform-acct> --repository <team>-<product>
# points pip at the repo index-url with a token; then `pip install` as usual
```

### NuGet / dotnet

```bash
aws codeartifact login --tool dotnet --region us-east-1 \
  --domain refplat --domain-owner <platform-acct> --repository <team>-<product>
```

### Maven (no `login` helper — configure `settings.xml`)

```bash
export CODEARTIFACT_TOKEN=$(aws codeartifact get-authorization-token --region us-east-1 \
  --domain refplat --domain-owner <platform-acct> --query authorizationToken --output text)
ENDPOINT=$(aws codeartifact get-repository-endpoint --region us-east-1 \
  --domain refplat --domain-owner <platform-acct> --repository <team>-<product> \
  --format maven --query repositoryEndpoint --output text)
# put ${ENDPOINT} as a <repository> and ${CODEARTIFACT_TOKEN} as the server password in settings.xml
```

Public dependencies resolve transparently through the store-repo upstreams — you do **not** point your tool at
npmjs/PyPI directly; point it at your Product repo and CodeArtifact proxies the rest.

## Publish

Your Product's CI OIDC role can already publish to `refplat/<team>-<product>` (scoped to your Product only). After
`aws codeartifact login` (npm/dotnet) or `... --tool twine` (Python), publish with the tool's normal command
(`npm publish`, `twine upload`, `mvn deploy`, `dotnet nuget push`). Publishing to another Product's repo is denied.

## In CI

Add a login step before your install/publish step. In GitHub Actions (the OIDC role is already assumed by the
shared build workflow's identity):

```yaml
- name: CodeArtifact login (npm)
  run: |
    aws codeartifact login --tool npm --region us-east-1 \
      --domain refplat --domain-owner ${{ '{{' }} secrets.PLATFORM_ACCOUNT_ID {{ '}}' }} \
      --repository ${TEAM}-${PRODUCT}
```

(The shared `trusted-ci` build workflows do not run this by default — add it in your repo's workflow when your
build actually needs private packages or upstream-cached public ones.)

## Troubleshooting

- **`Could not connect to the endpoint URL` / 403 on install** — token expired (≤12h) or you're authenticated to
  the wrong AWS account/role. Re-run `aws codeartifact login`.
- **A public package 404s** — the store-repo upstream for that format may not be attached, or the package genuinely
  doesn't exist upstream. Confirm the repo has the expected upstream (`aws codeartifact describe-repository`).
- **Go** — not supported; this registry is for npm/PyPI/Maven/NuGet only (ADR-098 D5).

## Related

- [ADR-098](../adrs/098-package-registry-codeartifact.md) — the decision (CodeArtifact + ECR pull-through cache).
- [ADR-028](../adrs/028-ecr-cross-account-container-registry.md) — ECR, the container-image sibling.
- `infra/modules/aws/codeartifact/` — the module; `infra/live/aws/platform/us-east-1/platform/codeartifact/` — the domain + repos.
