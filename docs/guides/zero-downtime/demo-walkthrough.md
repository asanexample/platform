# Demo walkthrough — see zero-downtime work

Three runnable demos that show the safety nets live: a **healthy canary promoting**, the **metric
gate's rollback decision**, and the **error-budget freeze**. The first is a real (benign) deploy; the
gate/freeze demos use standalone `AnalysisRun`s so you can show the decision logic **without breaking
an app**. All three have been run live on this platform.

**Prereqs:** Tailscale, `kubectl argo rollouts`, and `kubectl` against the cluster running the
rollout (preprod for tenant prod apps). Substitute `<ns>` = `<team>-<product>-prod`,
`<app>` = `app-<team>-<product>`.

## Demo 1 — a healthy canary promotes (end-to-end)

Deploy a benign change and watch real traffic shift gradually.

```bash
# in a terminal, start watching before you merge the prod Release
kubectl argo rollouts get rollout <app> -n <ns> --watch
```

Merge a small change → approve the prod Release. Narrate the watch output as it moves:

1. **Pre-flight freeze passes** — the rollout starts (the service was healthy).
2. **`setWeight: 25`** — `⟳ canary 25% / ✔ stable 75%`; it pauses while the metric gate samples.
3. **25 → 50 → 100** — each step holds for the gate, then advances.
4. **`Status: ✔ Healthy`**, canary becomes stable at 100%.

Point at **Grafana → Argo Rollouts** (status/weights) and **→ SLO dashboard** (burn rate flat). The
takeaway: *traffic moved in stages, was watched the whole way, and no request hit a half-deployed
service.*

## Demo 2 — the metric gate's rollback decision

The gate promotes while success rate ≥ 95% and aborts otherwise. Show **both verdicts**
deterministically with a standalone `AnalysisRun` (a `vector()` query stands in for the live RED
metric, so nothing real has to fail):

```yaml
# gate-demo.yaml — apply twice, flipping the vector value
apiVersion: argoproj.io/v1alpha1
kind: AnalysisRun
metadata:
  name: gate-demo-healthy        # and gate-demo-bad with vector(0.5)
  namespace: <ns>
spec:
  metrics:
    - name: success-rate
      # the real template uses the Mimir success-rate query; vector() makes the verdict deterministic
      successCondition: "result[0] >= 0.95"
      provider:
        prometheus:
          address: <the same Mimir query address your prod AnalysisTemplate uses>
          query: "vector(0.99)"   # healthy -> Successful;  vector(0.5) -> Failed
```

```bash
kubectl apply -f gate-demo.yaml
kubectl -n <ns> get analysisrun gate-demo-healthy -o jsonpath='{.status.phase}'   # Successful
# repeat with vector(0.5) -> Failed   (in a real rollout, Failed => abort + roll back to stable)
```

So a canary whose success rate drops below 95% drives the rollout `Degraded` and shifts traffic back
to stable — automatically. (To show it on a *real* rollout, deploy a deliberately-5xx image to a
throwaway environment and watch the abort — more theatrical, but it breaks a real app, so keep it off
prod.)

## Demo 3 — the error-budget freeze

The freeze is the pre-flight gate: it aborts the deploy if the service is already burning budget
`≥ 2×`. Same trick — flip the `vector()` to straddle the threshold:

```yaml
# freeze-demo.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisRun
metadata:
  name: freeze-demo
  namespace: <ns>
spec:
  metrics:
    - name: budget-freeze
      count: 1
      successCondition: "len(result) == 0 || result[0] < 2"
      provider:
        prometheus:
          address: <the same Mimir query address your prod AnalysisTemplate uses>
          # real query: slo:current_burn_rate:ratio{sloth_id="<ns>-availability"}
          query: "vector(3)"     # burning 3x -> Failed (frozen);  vector(0.5) -> Successful (deploy proceeds)
```

```bash
kubectl apply -f freeze-demo.yaml
kubectl -n <ns> get analysisrun freeze-demo -o jsonpath='{.status.phase}'   # Failed -> would freeze
```

In a real deploy this runs as **step 0**, so a service already over budget is frozen **before any
traffic shifts** — the platform refuses to pile change onto an in-progress incident. Show the live
burn rate on **Grafana → SLO dashboard** alongside it.

## Cleanup

```bash
kubectl -n <ns> delete analysisrun gate-demo-healthy gate-demo-bad freeze-demo 2>/dev/null
```

## Talking points

- **Two questions, two gates:** "is the new version healthy?" (metric gate → rollback) vs "is the
  service healthy enough to deploy?" (freeze → don't deploy).
- **No instrumentation:** the signals are Beyla RED metrics — apps get gated with zero code.
- **GitOps-native:** the rollback of record is reverting the promotion; the gates make the *common*
  case automatic.

## See also

- [Developer tutorial](tutorial-first-deploy.md) (the happy path, hand-held) ·
  [Platform internals](overview-platform.md) ·
  [Operations runbook](../../runbooks/rollout-and-gate-operations.md)
