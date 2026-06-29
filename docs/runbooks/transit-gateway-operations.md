# Runbook: Transit Gateway Operations

> **Module path:** `infra/modules/aws/transit-gateway`
> **Live configurations:**
>
> - `infra/live/aws/platform/us-east-1/platform/transit-gateway/terragrunt.hcl` (hub)
> - `infra/live/aws/preprod/us-east-1/platform/transit-gateway/terragrunt.hcl` (spoke)
>
> **Related ADR:** [034-transit-gateway-cross-account-connectivity](../adrs/034-transit-gateway-cross-account-connectivity.md)
>
> **Last reviewed:** 2026-05-28

---

## Table of Contents

1. [Architecture](#architecture)
2. [Adding a New Spoke Account](#adding-a-new-spoke-account)
3. [Adding Routes to an Existing Spoke](#adding-routes-to-an-existing-spoke)
4. [Verifying Connectivity](#verifying-connectivity)
5. [Troubleshooting](#troubleshooting)

---

## Architecture

The Transit Gateway uses a hub-and-spoke model for cross-account VPC
connectivity.

```text
Platform VPC (10.100.0.0/16)          Preprod VPC (10.101.0.0/16)
  |                                      |
  |-- transit subnets (/28 per AZ)       |-- transit subnets (/28 per AZ)
  |        |                             |        |
  +--------+-----------------------------+--------+
           |                             |
     TGW Attachment                TGW Attachment
           |                             |
           +-------- Transit Gateway ----+
                   (platform account)
                   Shared via RAM
```

| Component | Account | Purpose |
|-----------|---------|---------|
| Transit Gateway | Platform (<PLATFORM_ACCOUNT_ID>) | Hub -- owns the TGW |
| RAM Share | Platform | Shares TGW to spoke accounts |
| VPC Attachment (platform) | Platform | Connects platform VPC |
| VPC Attachment (preprod) | Preprod (<PREPROD_ACCOUNT_ID>) | Connects preprod VPC |
| Routes (platform) | Platform | 10.101.0.0/16 -> TGW |
| Routes (preprod) | Preprod | 10.100.0.0/16 -> TGW |
| SG Rule (preprod) | Preprod | Allows 443 from 10.100.0.0/16 on EKS cluster SG |

Both VPCs use dedicated `/28` transit subnets per AZ for TGW ENIs. These
are separate from the node/pod subnets to avoid routing conflicts.

---

## Adding a New Spoke Account

This procedure adds a new VPC to the Transit Gateway. The hub (platform
account) shares the TGW via RAM, and the spoke account accepts the share
and attaches its VPC.

### Prerequisites

- [ ] The new account's VPC is deployed with transit subnets (`/28` per AZ).
- [ ] You have the new account's VPC ID, transit subnet IDs, and route
  table IDs.
- [ ] You have `AWS_PROFILE=management` configured (Terragrunt assumes
  PlatformDeployer in each account).
- [ ] You are on a feature branch.

### Step 1: Add the Account to the Hub RAM Share

Edit `infra/live/aws/platform/us-east-1/platform/transit-gateway/terragrunt.hcl`
and add the new account ID to `ram_share_principals`:

```hcl
ram_share_principals = [
  "<PREPROD_ACCOUNT_ID>",   # preprod
  "<PROD_ACCOUNT_ID>",   # prod (NEW)
]
```

Apply:

```bash
cd infra/live/aws/platform/us-east-1/platform/transit-gateway
AWS_PROFILE=management terragrunt apply
```

Expected: new `aws_ram_principal_association` resource created.

### Step 2: Create the Spoke Unit

Create the spoke Terragrunt unit for the new account. Use the preprod
unit as a template:

```bash
cp -r infra/live/aws/preprod/us-east-1/platform/transit-gateway \
      infra/live/aws/prod/us-east-1/platform/transit-gateway
```

Edit the new `terragrunt.hcl` to reference the correct networking
dependency and set the appropriate `destination_cidrs` (the platform
VPC CIDR):

```hcl
inputs = {
  create     = true
  create_tgw = false   # spoke mode

  name = "${local.env}-${local.region_abbv}-tgw"

  transit_gateway_id = dependency.platform_tgw.outputs.transit_gateway_id
  ram_share_arn      = dependency.platform_tgw.outputs.ram_share_arn

  vpc_id = dependency.networking.outputs.vpc_id

  # networking exposes one `subnet_ids` map (name -> id); filter to the transit-tier
  # subnets (/28 per AZ, dedicated to TGW ENIs) — there is no `transit_subnet_ids` output.
  subnet_ids = [
    for name, id in dependency.networking.outputs.subnet_ids :
    id if can(regex("transit$", name))
  ]

  route_table_ids  = dependency.networking.outputs.private_route_table_ids
  destination_cidrs = ["10.100.0.0/16"]   # platform VPC

  security_group_id          = dependency.eks.outputs.cluster_security_group_id
  security_group_ingress_cidrs = ["10.100.0.0/16"]

  tags = local.tags
}
```

Apply:

```bash
cd infra/live/aws/prod/us-east-1/platform/transit-gateway
AWS_PROFILE=management terragrunt apply
```

Expected: RAM share accepted, VPC attachment created, routes added, SG
rules created.

### Step 3: Add Return Routes on the Hub

Update the platform hub unit to add routes to the new spoke VPC:

```hcl
destination_cidrs = [
  "10.101.0.0/16",   # preprod
  "10.102.0.0/16",   # prod (NEW)
]
```

Apply:

```bash
cd infra/live/aws/platform/us-east-1/platform/transit-gateway
AWS_PROFILE=management terragrunt apply
```

### Step 4: Verify

See [Verifying Connectivity](#verifying-connectivity) below.

---

## Adding Routes to an Existing Spoke

To route additional CIDRs through the TGW (e.g., a new VPC in the
same account):

1. Add the CIDR to `destination_cidrs` in both the hub and spoke units.
2. Apply both units.

The module uses `setproduct(route_table_ids, destination_cidrs)` to
create one route per route-table/CIDR combination.

---

## Verifying Connectivity

### Check TGW State

```bash
# Hub account — TGW exists and attachments are available
AWS_PROFILE=platform aws ec2 describe-transit-gateways \
  --query 'TransitGateways[].{Id:TransitGatewayId,State:State,ASN:Options.AmazonSideAsn}'

# List all attachments
AWS_PROFILE=platform aws ec2 describe-transit-gateway-attachments \
  --query 'TransitGatewayAttachments[].{Id:TransitGatewayAttachmentId,State:State,VpcId:ResourceId,Account:ResourceOwnerId}'
```

All attachments should show `State: available`.

### Check Route Tables

```bash
# Platform account — verify routes to spoke CIDRs
AWS_PROFILE=platform aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<platform-vpc-id>" \
  --query 'RouteTables[].Routes[?TransitGatewayId!=null].{CIDR:DestinationCidrBlock,TGW:TransitGatewayId,State:State}'

# Spoke account — verify routes to platform CIDR (use the spoke's own profile;
# AWS_PROFILE=management won't see preprod resources without role assumption)
AWS_PROFILE=preprod aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<spoke-vpc-id>" \
  --query 'RouteTables[].Routes[?TransitGatewayId!=null].{CIDR:DestinationCidrBlock,TGW:TransitGatewayId,State:State}'
```

### Check RAM Share

```bash
# Hub account — share exists and has associations
AWS_PROFILE=platform aws ram get-resource-shares \
  --resource-owner SELF \
  --query 'resourceShares[?name==`platform-use1-tgw-share`].{Name:name,Status:status}'

# Spoke account — share is accepted
AWS_PROFILE=preprod aws ram get-resource-share-invitations \
  --query 'resourceShareInvitations[].{Name:resourceShareName,Status:status}'
```

### Test IP Connectivity

From a pod on the platform cluster, test connectivity to the spoke VPC:

```bash
# Get a node IP from the spoke cluster (read with the spoke's own profile)
SPOKE_NODE_IP=$(AWS_PROFILE=preprod aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=preprod-use1-eks" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

# Test from the platform cluster
kubectl run tgw-test --rm -it --restart=Never --image=busybox:1.36 \
  -- wget -qO- --timeout=5 "http://${SPOKE_NODE_IP}:10250/healthz" 2>&1 || echo "Expected: connection refused or timeout (port 10250 is kubelet, confirms IP reachability)"
```

For HTTPS (EKS API), test port 443:

```bash
kubectl run tgw-test --rm -it --restart=Never --image=busybox:1.36 \
  -- nc -zv -w5 <spoke-eks-api-ip> 443
```

---

## Troubleshooting

### TGW Attachment Stuck in "pendingAcceptance"

**Cause:** The RAM share has not been accepted by the spoke account, or
`auto_accept_shared_attachments` is disabled on the TGW.

**Fix:**

```bash
# Check RAM share status in spoke account
AWS_PROFILE=preprod aws ram get-resource-share-invitations \
  --query 'resourceShareInvitations[].{Status:status,ShareArn:resourceShareArn}'

# If pending, Terragrunt should accept it via aws_ram_resource_share_accepter.
# Re-apply the spoke unit:
cd infra/live/aws/preprod/us-east-1/platform/transit-gateway
AWS_PROFILE=management terragrunt apply
```

### Routes Not Appearing in Route Tables

**Cause:** The route table IDs passed to the module do not match the
actual route tables for the VPC's private subnets.

**Fix:**

```bash
# List route tables for the VPC
AWS_PROFILE=platform aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'RouteTables[].{Id:RouteTableId,Associations:Associations[].SubnetId}'

# Compare with the route_table_ids input in terragrunt.hcl
cd infra/live/aws/platform/us-east-1/platform/transit-gateway
terragrunt output
```

The networking module outputs `private_route_table_ids` as a map. Verify
the spoke unit references this output correctly.

### Cross-VPC Traffic Times Out

**Cause:** Security group rules are missing, routes are asymmetric, or
NACLs are blocking traffic.

**Debug checklist:**

1. **Routes exist in both directions:**

   ```bash
   # Platform -> Spoke route exists
   AWS_PROFILE=platform aws ec2 describe-route-tables \
     --filters "Name=vpc-id,Values=<platform-vpc-id>" \
     --query 'RouteTables[].Routes[?DestinationCidrBlock==`10.101.0.0/16`]'

   # Spoke -> Platform route exists
   AWS_PROFILE=preprod aws ec2 describe-route-tables \
     --filters "Name=vpc-id,Values=<preprod-vpc-id>" \
     --query 'RouteTables[].Routes[?DestinationCidrBlock==`10.100.0.0/16`]'
   ```

2. **Security groups allow traffic:**

   The module adds ingress rules to the EKS cluster security group on
   port 443. Check that the SG rule exists:

   ```bash
   AWS_PROFILE=preprod aws ec2 describe-security-group-rules \
     --filters "Name=group-id,Values=<eks-cluster-sg-id>" \
     --query 'SecurityGroupRules[?CidrIpv4==`10.100.0.0/16`]'
   ```

3. **NACLs are not blocking:** Transit subnets use the VPC's default
   NACL (allow all). Verify no custom NACLs were added.

4. **TGW route table propagation:** The TGW uses default route table
   association and propagation. Verify:

   ```bash
   AWS_PROFILE=platform aws ec2 search-transit-gateway-routes \
     --transit-gateway-route-table-id <tgw-rtb-id> \
     --filters "Name=type,Values=propagated"
   ```

### ArgoCD Cannot Reach Preprod Cluster API

ArgoCD on the platform cluster accesses the preprod EKS API over the TGW.
If ArgoCD applications show connection errors:

1. Verify TGW connectivity (see above).
2. Check cross-VPC DNS resolution. ArgoCD uses the preprod EKS endpoint
   hostname, which resolves via a Private Hosted Zone managed by the
   `cross-vpc-dns` unit. See [ADR-035](../adrs/035-cross-vpc-dns-resolution.md).

   ```bash
   # From the platform cluster, verify DNS resolution
   kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 \
     -- nslookup <preprod-eks-endpoint-hostname>
   ```

3. Check the ArgoCD cluster secret:

   ```bash
   argocd cluster list | grep preprod
   ```

### Terraform State Drift After Manual Changes

If someone manually modified TGW routes or attachments:

```bash
cd infra/live/aws/platform/us-east-1/platform/transit-gateway
terragrunt plan
# Review drift and apply to reconcile
```

The module is idempotent -- applying will reconcile state to match the
declared configuration.
