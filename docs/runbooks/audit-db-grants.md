# Activation audit DB — least-privilege grants (ADR-088 §3.6)

The activation operator writes the durable borrow audit to the ADR-084 directory Postgres
(`activation_audit` table). The operator + Backstage no longer connect as the `directory` owner — they use
two **scoped roles** so neither can touch the directory's identity tables:

| Role | Used by | Privilege |
|------|---------|-----------|
| `activation_writer` | the activation operator | `INSERT` on `activation_audit` (+ `CREATE` on schema so it can create the table on a greenfield cluster) |
| `activation_reader` | the Backstage `activate-power` backend (My Access history) | `SELECT` on `activation_audit` |

The roles are created declaratively by the `platform-directory` CNPG cluster (`managed.roles`), and their
connections are published to Secrets Manager (`platform/activation-operator/audit-writer-db`,
`platform/backstage/audit-reader-db`). But the **table is operator-created at runtime**, so the table-level
grants can't be declarative — run them **once** as the `directory` owner:

```sql
GRANT USAGE, CREATE ON SCHEMA public  TO activation_writer;
GRANT USAGE          ON SCHEMA public  TO activation_reader;
GRANT INSERT ON activation_audit             TO activation_writer;
GRANT USAGE  ON SEQUENCE activation_audit_id_seq TO activation_writer;
GRANT SELECT ON activation_audit             TO activation_reader;
```

## Running it

The directory DB is private; the CiliumNetworkPolicy admits `activation-system` + `backstage`. Run a
throwaway `psql` pod in an admitted namespace, reading the **directory owner** connection from the SM-projected
secret (never print the DSN):

```bash
# the directory owner connection lives in SM platform/triage-copilot/directory-db (uri). Project it transiently,
# or run from a pod that already has it. Example one-off (deployer context):
AWS_PROFILE=platform kubectl --context platform-deployer run audit-grants -n activation-system --rm -i \
  --restart=Never --image=postgres:16 \
  --overrides='{ ...securityContext: runAsNonRoot... }' \
  -- sh -c 'psql "$DSN" -f -' < this-file's-SQL
```

(Idempotent — re-running is harmless.) On a **from-scratch rebuild** the operator's `activation_writer` role
has `CREATE` on the schema, so it creates the table itself on first connect; then re-run the `GRANT SELECT …
TO activation_reader` so Backstage can read it.

## Why one-time, not declarative

CNPG's `postInitApplicationSQL` only runs at cluster bootstrap, and races the `managed.roles` creation; and the
`activation_audit` table is owned/created by the operator at runtime, not by the DB module. So the role
creation is declarative (survives reconciles) while the table grants are this documented one-off — see
[ADR-088 § Implementation notes](../adrs/088-temporary-power-activation.md#implementation-notes-as-built).
