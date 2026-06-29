# Activation operator

The **temporary-power activation controller** of [ADR-088](../../docs/adrs/088-temporary-power-activation.md)
— a Kubebuilder/controller-runtime operator that lets an eligible operator **borrow** a dangerous power for a
bounded window and yanks it back on expiry or revoke. Design:
[`docs/architecture/temporary-power-activation-controller.md`](../../docs/architecture/temporary-power-activation-controller.md).

It is the always-on, timer-owning cousin of the `platctl access grant/revoke` CLI (which stays the
controller-down break-glass recovery floor). An `Activation` custom resource is one borrowed-power window;
the controller mints/expires/revokes the native grant across projection **planes**.

## Scope of this increment

This is **increment 1** — a working vertical slice:

- the cluster-scoped **`Activation` CRD** (`platform.refplat.org/v1alpha1`);
- the reconcile **lifecycle** (finalizer, requeue-to-expiry, leak-safe teardown), with `status.expiresAt`
  as the crash-safe expiry clock;
- the **AWS Identity Center plane** (AWS SDK Go v2): a temporary `USER` account-assignment to the role's
  permission set across the accounts it is provisioned to, minted/revoked **asynchronously and serialized
  per permission set** (the AWS behavior the `platctl` live test exposed);
- **full OpenTelemetry telemetry** (traces + metrics over OTLP) and the leaked-grant signal.

The operator reads the **role catalog** (in-cluster `WorkforceRole` CRs, git-projected) to **enforce the
borrow cap** (`expiresAt = grantedAt + min(spec.duration, role.sessionDuration)`) and resolve the AWS
permission set — failing closed on a role it can't find.

**Deferred (later increments):** the imperative intake API + passkey step-up (the *sole* CR-creator), the
**eligibility re-check** (Person CRs) + drift backstop, the Postgres audit sink, hub delivery (incl. installing
the `WorkforceRole` CRD on the hub + syncing `gitops/roles`), the Keycloak and cluster (Teleport) planes, and
the `revoke-all` kill-switch.

## ⚠️ Security posture (increment 1)

There is **no intake API or step-up yet**, so **`create` permission on `activations` is the entire security
boundary** — anyone who can create one gets the borrowed power with no step-up. Therefore:

- **Lock `create`/`update`/`delete` on `activations` to a named admin/operator ServiceAccount** at delivery
  time. This increment is **NOT safe to expose to self-service.**
- The operator **fails closed**: on any uncertainty (role not in the catalog, AWS error) it does not grant.
- The duration **cap IS enforced** from the role catalog; an unbounded-duration request is capped to the role's
  `sessionDuration`. (The *eligibility* re-check — who may borrow what — is still the deferred intake API's job;
  the bound on who can request is create-RBAC.)

## Configuration

| Flag | Default | Purpose |
|------|---------|---------|
| `--aws-region` | `us-east-1` | Identity Center region. |
| `--sync-period` | `2m` | Cache resync — the safety net that re-reconciles every Activation so a dropped expiry timer self-heals while the drift backstop is deferred. |
| `--leader-elect` | `false` | Active-passive HA (enable in delivery; ≥2 replicas). |

AWS auth is **EKS Pod Identity** in cluster (not IMDS). `OTEL_EXPORTER_OTLP_ENDPOINT` enables telemetry
export (no-op when unset).

## Develop

```bash
make manifests generate   # regenerate CRDs + deepcopy after editing api/v1alpha1
make test                 # unit + envtest (provisions envtest assets)
make lint vet             # golangci-lint (incl. staticcheck) + go vet
make run                  # run locally against your kubeconfig
```

From the repo root: `make build-operator`, `make test-operator`, `make operator-manifests`.

## Telemetry

Unified OTel pipeline → the cluster otel-collector → Mimir/Tempo, plus structured logs → Loki:

- **metrics:** `activation_active` (by role), `activation_leaked` (must be 0), mint/revoke duration
  histograms, mint/revoke failure counters, + controller-runtime's reconcile metrics;
- **traces:** a span per reconcile and per async AWS operation (create/poll/delete), with account /
  permission-set attributes;
- **logs:** structured, trace-correlated, never carrying tokens/secrets.

A Grafana dashboard-as-code and curated alerts accompany the operator's delivery.
