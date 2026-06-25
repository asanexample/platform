# MCP Servers (Claude Code)

The repo ships a project-scoped `.mcp.json` wiring two **read-only** MCP servers for
agent-assisted debugging. Both are first-party (Grafana, AWS) and configured read-only by
design — see the security notes below. Claude Code prompts each developer to approve
project MCP servers on first use.

| Server | Purpose | Transport | Reaches |
|--------|---------|-----------|---------|
| `grafana` | Query dashboards, Prometheus/Loki/Tempo, alerts/incidents (the LGTM+P stack) | local binary (stdio) | `grafana.aws.refplat.org` — **Tailscale-only** |
| `aws-api` | Read-only AWS API for debugging (EC2/EKS/IAM/ECR/CloudWatch/…) | `uvx` (stdio) | AWS control plane (no tailnet needed) |

## grafana

Runs the `mcp-grafana` binary on the host (a container can't reach the Tailscale-only Grafana),
with `--disable-write` so only read tools are exposed.

**Setup:**

1. Install the binary (once) — ensure `$HOME/go/bin` is on PATH, or download a release binary:

   ```bash
   GOBIN="$HOME/go/bin" go install github.com/grafana/mcp-grafana/cmd/mcp-grafana@latest
   ```

2. Create a Grafana **service account with the `Viewer` role** and mint a token (Grafana →
   Administration → Service accounts). Viewer = read-only at the Grafana side, on top of the
   server's `--disable-write` flag (defense in depth).
3. Export the token (e.g. in your shell profile or a local, gitignored env file) — never commit it:

   ```bash
   export GRAFANA_SERVICE_ACCOUNT_TOKEN=glsa_xxx
   # export GRAFANA_URL=...   # optional; defaults to the prod Grafana
   ```

4. Be **on the tailnet** — Grafana has no public endpoint.

## aws-api

Runs `awslabs.aws-api-mcp-server` via `uvx`, with **`READ_OPERATIONS_ONLY=true`** — the server
refuses any AWS API call whose IAM access level is `Write`, regardless of what the underlying
role could do. Telemetry to AWS is disabled.

**Setup:**

1. Have `uv`/`uvx` installed (already standard here) and an active AWS SSO session.
2. The server uses the AWS profile named by `AWS_API_MCP_PROFILE_NAME` (default `management`);
   override per target account:

   ```bash
   export AWS_API_MCP_PROFILE_NAME=platform   # or preprod, etc.
   aws sso login --profile "$AWS_API_MCP_PROFILE_NAME"
   ```

## Verify

```bash
claude mcp list   # both should report Connected once env vars are set
```

## Security notes

- **Read-only by construction.** `aws-api` is pinned to `READ_OPERATIONS_ONLY=true`; `grafana`
  runs with `--disable-write` and (recommended) a Viewer service account. Do not relax these in
  the committed config — this repo controls IAM and admission policy.
- **No secrets in git.** The Grafana token and AWS credentials come from your environment /
  SSO; `.mcp.json` only references env vars.
- **Credential blast radius.** `aws-api` inherits whatever the chosen profile can see (read).
  Prefer a least-privilege profile (e.g. `PlatformAdmin`/read roles) over `PlatformDeployer`
  where you can.
- **Headless gap.** These are local stdio servers, so they work in interactive sessions; a
  scheduled/cron agent would need the same binaries + env present in its environment.
