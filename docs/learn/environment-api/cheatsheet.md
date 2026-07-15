# Cheatsheet — Environment API commands

Commands for working with the concepts in this module: inspecting an environment, reading its status,
debugging a stuck resource, verifying the real AWS resources. Every command here is run-verified. It's a
lookup, not an explainer — [the orientation](orientation.md) covers what these mean.

**Access notes:**

- **`kubectl`** reaches the private preprod cluster over Tailscale as PlatformAdmin. `./bin/platctl
  kubeconfig` sets up the contexts (platctl is built with `make build-platctl` — it's not on `PATH`;
  see the `platctl` / `cluster-access` skills). The Environment API runs on preprod, not the hub, so
  always pass `--context preprod`.
- **`crossplane`** needs the CLI; `render` also needs Docker but no cluster (fully offline).
- **`aws`** needs a profile — `platform` for ECR (the platform account), `preprod` for the workload
  account (IAM, Pod Identity).

## Render a claim — offline, no cluster

```console
cd infra/modules/crossplane/.environment-api-tests
crossplane render environments/demo-dev.yaml ../charts/environment-api/files/composition.yaml \
  render/functions.yaml --extra-resources render/environmentconfig.yaml   # the footprint, as YAML
./render.sh                                                               # render the fixtures + assert
```

## Inspect an environment

```console
# list every environment (drop the name); or one environment's SYNCED / READY status
kubectl --context preprod get xenvironment
kubectl --context preprod get xenvironment alpha-shop-dev

# the whole footprint as a tree — fast, and the best "what did this create?" view
crossplane resource trace xenvironment alpha-shop-dev --context preprod

# the in-cluster resources only — kubectl-only and fast (the composite label filters)
kubectl --context preprod get object -l crossplane.io/composite=alpha-shop-dev

# the environment's bound hostnames
kubectl --context preprod get xenvironment alpha-shop-dev -o jsonpath='{.status.domains}'
```

> Avoid `kubectl get managed` for this — it fans out over *every* provider CRD (~20s, looks hung). Use
> `trace` or the label-filtered `get object` above.

## Debug a stuck resource

Managed resources carry a random hash suffix, so grab the real `<mr-name>` from `trace` or `get object`
above first. The examples use the IAM role; the same works for **any** managed-resource kind
(`repository.ecr.aws.upbound.io`, `object.kubernetes.crossplane.io`, …).

```console
# read a managed resource's Synced / Ready conditions (+ reasons)
kubectl --context preprod get role.iam.aws.upbound.io <mr-name> \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'

# the full story — a Synced=False condition's MESSAGE carries the real cause (denied IAM, bad field, …)
kubectl --context preprod describe role.iam.aws.upbound.io <mr-name>
```

## Verify the real AWS resources

```console
# the ECR repo lives in the PLATFORM account (the one cross-account hop)
aws ecr describe-repositories --repository-names team-alpha/shop-storefront --profile platform \
  --query 'repositories[0].repositoryUri' --output text
# → <platform-acct>.dkr.ecr.us-east-1.amazonaws.com/team-alpha/shop-storefront

# the service's IAM role lives in the WORKLOAD account
aws iam get-role --role-name Pod-alpha-shop-dev-storefront --profile preprod \
  --query 'Role.Arn' --output text
# → arn:aws:iam::<workload-acct>:role/Pod-alpha-shop-dev-storefront
```

## See also

- [Tutorial: render your first environment](tutorial-render-an-environment.md) — the guided, do-it version.
- [Reference](reference.md) · [Orientation](orientation.md) · the [portal glossary](../glossary.md).
