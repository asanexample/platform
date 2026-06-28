# Documentation Audit — observability module READMEs (17 modules)

Checkout @ origin/main. Clusters parked; verification against repo only. All 17 modules have a README. **Chart-version drift: none** (all 14 pins match `_versions.hcl`).

## infra/modules/observability/README.md

- [SEVERITY: medium] Silent on several now-built major features — Grafana **Keycloak OIDC SSO** (`grafana_oidc_*`, #592), the **Slack** receiver, the **PagerDuty** receiver, the **triage-agent** fan-out (`triage_webhook_url`, ADR-082), and the **Grafana CloudWatch datasource** (`cloudwatch_enabled`, P5a). Prose still implies admin-password-only + SNS/email. — **Evidence:** `variables.tf:187-265`. — **Fix:** add "Alerting receivers (SNS/Slack/PagerDuty/triage)" + "Grafana SSO (Keycloak OIDC)" + CloudWatch-datasource notes.
- [SEVERITY: low] Key-inputs table omits `cluster_label` (the multi-cluster `externalLabels{cluster}` dimension). — **Evidence:** `variables.tf:12-16`.

## infra/modules/observability-alloy/README.md

- [SEVERITY: low] Prose writes the tenant as `_platform` (leading underscore) twice; actual `tenant_id` default is `platform`. Silent on `external_labels`. — **Evidence:** `variables.tf:19-28`. — **Fix:** write `platform`; add `external_labels`.

## infra/modules/observability-beyla/README.md — accurate (chart 1.16.8)

## infra/modules/observability-blackbox/README.md — accurate (chart 11.13.0)

## infra/modules/observability-cloudwatch-exporter/README.md — accurate (Pod Identity, no IRSA; chart 0.46.0)

## infra/modules/observability-events/README.md — accurate (chart 1.10.0)

## infra/modules/observability-k6/README.md — accurate (image grafana/k6:0.55.0)

## infra/modules/observability-loki/README.md

- [SEVERITY: high] Stale architecture claim: "Key decisions" says *"(The rest of the observability stack still uses IRSA — tracked for migration in the IRSA→Pod-Identity epic.)"* — no longer true. Mimir, Tempo, Pyroscope, cloudwatch-exporter, and the hub Alertmanager/Grafana have all moved to EKS Pod Identity (ADR-047/#594); a grep for `eks.amazonaws.com/role-arn` across all observability modules returns only negations. Misleads on the stack-wide auth model. — **Evidence:** `README.md:12-13` vs `observability-mimir/README.md:7`, `observability-tempo/README.md:15`, `observability-pyroscope/README.md:11`, `observability/variables.tf:135`. — **Fix:** delete the parenthetical (or "the rest of the stack has likewise migrated to Pod Identity").
- [SEVERITY: low] Self-referential typo: "SingleBinary … same pattern as Mimir/**Loki**" → should be Mimir/Tempo.

## infra/modules/observability-mimir/README.md

- [SEVERITY: medium] Thin coverage of major shipped features — nothing about the **ruler** (`enable_ruler`/`ruler_tenants`/`ruler_alertmanager_url`, P4), **per-app SLO burn-rate rules** (`app_slos`, ADR-056), **cross-cluster `spoke_ingest`** (P10), federated/extra-tenant datasources, or exemplar/label-cap tuning. — **Evidence:** `variables.tf:130-245`. — **Fix:** add a "Hub-only extras (ruler · app SLOs · spoke ingest)" section.
- [SEVERITY: low] Duplicated-word typo "…and an / An IAM role" (`README.md:6-7`).

## infra/modules/observability-opencost/README.md — accurate (chart 2.5.23)

## infra/modules/observability-otel-collector/README.md

- [SEVERITY: low] Gap: "Key decisions" don't mention the **spoke/HTTP export mode** (`exporter_use_http`, `tenant_id`, `resource_attributes`) that makes this double as a spoke trace forwarder. — **Evidence:** `variables.tf:19-41`. — **Fix:** add a "hub (gRPC) vs spoke (OTLP/HTTP edge)" note. Chart 0.158.2.

## infra/modules/observability-otel-operator/README.md — accurate (chart 0.116.0)

## infra/modules/observability-prometheus-agent/README.md — accurate (chart 86.1.0, reuses hub pin)

## infra/modules/observability-pyroscope/README.md — accurate (Pod Identity, chart 2.1.0)

## infra/modules/observability-pyroscope-ebpf/README.md — accurate (chart 1.10.0)

## infra/modules/observability-slo/README.md — accurate (Sloth, chart 0.16.0)

## infra/modules/observability-tempo/README.md

- [SEVERITY: low] "Key decisions" flatly state "metrics-generator off … defer with Mimir," but the module now exposes `enable_metrics_generator` (P6/APM RED span-metrics + service graph), `enable_traces_to_profiles`, `spoke_ingest`. Reads as permanently off. — **Evidence:** `variables.tf:52-80`. — **Fix:** "metrics-generator off by default (opt in via `enable_metrics_generator` for P6 APM)". Chart 2.25.5.

---

## Cross-cutting note

- **The IRSA→Pod Identity migration (ADR-047/#594) is fully reflected in every module's code and every README except `observability-loki`** — the lone stale outlier, asserting the rest of the stack runs on IRSA. Fix loki and the auth story is internally consistent.
- **Chart-version drift: none.** All 14 pins match `_versions.hcl` exactly.
- **No missing READMEs; all cross-references resolve.**
- **Recurring gap pattern:** the hub (`observability`) and `mimir` READMEs were written early and haven't kept pace with later phases (SSO, extra alert receivers, ruler/app-SLOs, spoke ingest). Their key-inputs tables are explicitly curated subsets — documentation lag, not contradiction — worth a refresh.
