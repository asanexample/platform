# tenant-proxy — P13 per-team read isolation front door

A small, stateless reverse proxy that enforces **per-team read isolation** over the shared
observability stores (Mimir/Loki/Tempo). It is the **read half** of P13 (#590, ADR-043/044): the
stores already isolate by tenant (`X-Scope-OrgID`), but OSS Grafana has no per-user datasource
gating, so *something* must translate "who is asking" into "which tenants they may read." This is
that something.

## Why it exists

Grafana forwards the logged-in user's Keycloak OIDC token to a datasource when `oauthPassThru` is
enabled — as the **`X-Id-Token`** header (confirmed live in the P13 spike, #590). This proxy sits
between Grafana and the store:

```text
Grafana ──(query + X-Id-Token)──▶ tenant-proxy ──(query + X-Scope-OrgID=<team[s]>)──▶ Mimir/Loki/Tempo
```

For each request it:

1. Reads `X-Id-Token`. Missing → **401** (fail closed).
2. Verifies the JWT via the realm JWKS — signature, issuer, audience, expiry (coreos/go-oidc, with
   JWKS caching + rotation). Invalid → **401**.
3. Resolves the caller's `groups` claim to a tenant scope (`internal/tenant`):
   - the **admin group** → the federated scope over all tenants (`alpha|bravo|platform`);
   - otherwise the intersection of the user's groups with the known team tenants, `|`-joined;
   - no match → **403**. A group that is not a known tenant can never widen access.
4. **Overwrites** `X-Scope-OrgID` with the resolved scope (any inbound value is a spoof and is
   discarded), **strips** `X-Id-Token`, and reverse-proxies upstream.

Team groups are named exactly as the team identifier (`alpha`, `bravo`, `platform`, …), so no
mapping table is needed — the spike confirmed this.

## Fail-closed by construction

The single most important property: a request that is not positively authenticated **and** resolved
to a non-empty tenant scope is rejected before it reaches the store. Tests lead with the deny paths
(`internal/tenant`, `internal/proxy`, `internal/auth`) — missing/expired/wrong-issuer/wrong-audience/
bad-signature tokens, unknown teams, and empty group sets all deny; an inbound `X-Scope-OrgID` is
always overwritten; the user token is never forwarded upstream.

## Configuration (env)

| Var | Required | Default | Meaning |
|-----|----------|---------|---------|
| `UPSTREAM_URL` | ✓ | | store query API, e.g. `http://mimir-gateway.observability.svc/prometheus` |
| `JWKS_URL` | ✓ | | realm JWKS endpoint (`…/protocol/openid-connect/certs`) |
| `OIDC_ISSUER` | ✓ | | expected `iss` (`…/realms/platform`) |
| `OIDC_AUDIENCE` | ✓ | | expected `aud` (the Grafana OIDC client id) |
| `TENANTS` | ✓ | | comma-separated known team tenants (`alpha,bravo,platform`) |
| `ADMIN_GROUP` | ✓ | | group granting federated all-tenant reads (`platform-admins`) |
| `LISTEN_ADDR` | | `:8080` | proxy listen address |
| `METRICS_ADDR` | | `:9090` | `/metrics` + `/healthz` address (separate port) |
| `UPSTREAM_TIMEOUT` | | `30s` | upstream response-header timeout |

## Observability

`tenant_proxy_requests_total{result}` counts every decision — `allowed` or a stable deny reason
(`no_token`, `bad_token`, `no_tenant`, `resolve_error`). `/healthz` and `/metrics` are served on
`METRICS_ADDR` (no auth). Decisions are structured-logged (deny at INFO, allow at DEBUG).

## Develop

```bash
go test -race ./...     # unit + real-JWKS verification tests
go build ./...
docker build services/tenant-proxy
```

## Status / where this fits in P13

- **Done:** this service (code + tests). Zero blast radius — it does not touch the live write path.
- **Next (Phase 1):** re-tenant the metrics write path (cortex-tenant / relabel by team-from-namespace)
  so per-team tenants actually exist to read.
- **Then:** deploy this proxy, point one Grafana datasource at it with `oauthPassThru`, and gate the
  admin "all tenants" datasource to `platform-admins`; extend to logs/traces/profiles.

See the #590 design comment and `~/.claude/plans/590-per-team-isolation.md` for the full plan.
