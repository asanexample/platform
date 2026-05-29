# ADR-034: Transit Gateway for Cross-Account VPC Connectivity

**Date:** 2026-05-28

**Status:** Accepted

## Context

The platform spans multiple AWS accounts (platform <PLATFORM_ACCOUNT_ID>, preprod <PREPROD_ACCOUNT_ID>, prod
<PROD_ACCOUNT_ID>), each with its own VPC in private /16 CIDR ranges (platform `10.100.0.0/16`,
preprod `10.101.0.0/16`). EKS clusters run with private-only API endpoints (ADR-010), and
several cross-account connectivity requirements exist:

1. **ArgoCD multi-cluster management.** ArgoCD runs in the platform account and must reach the
   EKS API server in the preprod account to deploy workloads. The preprod cluster's API endpoint
   is private, so ArgoCD cannot reach it over the public internet.

2. **Tailscale subnet routing.** The Tailscale operator (ADR-011) runs in the platform cluster
   and advertises the platform VPC CIDR to the tailnet. Developers connected via Tailscale need
   to reach resources in spoke VPCs — particularly the preprod EKS API — without running a
   separate subnet router per account.

3. **Cross-VPC DNS resolution.** Private EKS API endpoints resolve to ENI IPs inside the VPC
   where the cluster lives. The platform account must resolve these private DNS names for the
   preprod cluster, which requires network-layer connectivity between the VPCs before DNS
   forwarding can work.

4. **Future spoke accounts.** The production account and any future accounts will need the same
   connectivity pattern. The solution must scale beyond a single pair of VPCs.

### Alternatives Considered

**1. VPC Peering.** One-to-one peering connections between each pair of VPCs. Simple to set up for
two VPCs, no additional infrastructure cost (data transfer only, ~$0.01/GB same-region). However,
VPC peering is non-transitive — traffic cannot flow from VPC A through VPC B to VPC C. With N
accounts, this requires N*(N-1)/2 peering connections, each with its own route table entries and
security group rules. Cross-account peering also requires manual acceptance per connection. This
works for a two-account setup but becomes unmanageable as the number of spoke accounts grows.
Rejected because the architecture is designed to scale to production and additional environments.

**2. Transit Gateway (chosen).** A regional network hub that connects multiple VPCs and on-premises
networks through a central point. Each VPC attaches to the TGW, and routes propagate automatically
through the TGW route table. Cross-account sharing is handled via AWS Resource Access Manager (RAM).
Adding a new spoke requires only one attachment and one RAM share acceptance — the hub does not need
to be reconfigured per spoke. Costs ~$0.05/hr per attachment (~$36/month) plus $0.02/GB data
processed.

**3. VPN or Direct Connect.** Site-to-site VPN tunnels between VPCs, or AWS Direct Connect for
on-premises-to-cloud connectivity. VPN adds IPsec overhead and complexity (BGP configuration,
tunnel monitoring, key rotation). Direct Connect is for physical datacenter connectivity, not
inter-VPC traffic. Neither is appropriate for VPC-to-VPC connectivity within the same region.
Rejected as overengineered for the use case.

## Decision

Adopt a **hub-and-spoke Transit Gateway pattern** with the platform account as the hub and all
other accounts as spokes. The implementation is a single reusable module
(`infra/modules/aws/transit-gateway/`) that supports both hub and spoke modes via the `create_tgw`
variable.

### Hub Mode (Platform Account)

When `create_tgw = true`, the module creates:

1. **Transit Gateway** with auto-accept for shared attachments, default route table association
   and propagation enabled, and DNS support enabled.

2. **RAM resource share** that shares the TGW with specified spoke account IDs via
   `ram_share_principals`. The platform hub shares with preprod (`<PREPROD_ACCOUNT_ID>`).

3. **VPC attachment** connecting the platform VPC to the TGW through dedicated transit subnets.

4. **Routes** in the platform VPC's private route tables directing spoke VPC CIDRs
   (`10.101.0.0/16` for preprod) through the TGW.

### Spoke Mode (Preprod, Prod, Future Accounts)

When `create_tgw = false`, the module:

1. **Accepts the RAM share** using the `ram_share_arn` output from the hub deployment.

2. **Attaches the spoke VPC** to the shared TGW using the `transit_gateway_id` output from
   the hub.

3. **Adds routes** in the spoke VPC's private route tables directing hub VPC traffic
   (`10.100.0.0/16`) through the TGW.

4. **Adds security group rules** (optional) to the EKS cluster security group allowing
   inbound HTTPS (port 443) from the hub VPC CIDR. This is required for ArgoCD to reach the
   spoke cluster's API endpoint.

### Transit Subnets

Each VPC has dedicated `/28` transit subnets (one per AZ) specifically for TGW ENIs. These are
defined in `network.hcl` as a `transit` subnet tier:

```hcl
transit = { newbits = 4, netnum = 15, public = false } # /28 (14 IPs)
```

The `/28` size provides 14 usable IPs per AZ, which is sufficient for TGW ENIs (one per AZ).
Dedicated transit subnets keep TGW ENIs isolated from workload subnets, simplifying network
ACLs and route table management.

### Dependency Graph

The spoke deployment depends on the hub being deployed first, since it consumes the hub's
`transit_gateway_id` and `ram_share_arn` outputs:

```hcl
# Spoke terragrunt.hcl
dependency "platform_tgw" {
  config_path = "../../../../platform/us-east-1/platform/transit-gateway"
}
```

Both hub and spoke depend on their respective `networking` module for VPC ID, subnet IDs, and
route table IDs. The spoke additionally depends on `eks` for the cluster security group ID.
All dependencies include `mock_outputs` so that `terragrunt destroy` works even when upstream
resources are already gone.

### Routing Configuration

The TGW default route table uses automatic association and propagation. All attached VPCs
automatically propagate their CIDR ranges to the TGW route table, and all attachments are
automatically associated with it. VPC-side routes are explicit: each VPC's private route
tables get a route for each remote CIDR pointing to the TGW.

| VPC | Route | Destination |
|-----|-------|-------------|
| Platform (`10.100.0.0/16`) | `10.101.0.0/16` -> TGW | Preprod VPC |
| Preprod (`10.101.0.0/16`) | `10.100.0.0/16` -> TGW | Platform VPC |

The module uses `setproduct` to generate a route for every combination of route table and
destination CIDR, ensuring all private subnets can reach remote VPCs.

## Consequences

**Positive:**

- Single hub configuration — adding a new spoke account requires only a new `ram_share_principals`
  entry on the hub and a spoke-mode deployment in the new account. No reconfiguration of existing
  spokes.
- Transitive routing — once connected to the TGW, any spoke can reach any other spoke through the
  hub. This eliminates the N*(N-1)/2 scaling problem of VPC peering.
- DNS support enabled on all attachments — combined with the cross-VPC DNS module, this enables
  private DNS resolution across accounts without additional networking.
- Auto-accept and default route table propagation minimize operational overhead. New attachments
  are accepted and routed automatically.
- The single module serves both hub and spoke roles, keeping the implementation DRY and consistent
  across accounts.
- Security group rules on the spoke side are optional and scoped to port 443 from specific CIDRs,
  maintaining least-privilege network access.

**Negative:**

- Cost — each TGW attachment costs ~$0.05/hr (~$36/month), and data processed through the TGW
  costs ~$0.02/GB. For two attachments (platform + preprod), the base cost is ~$72/month before
  data transfer. This increases linearly with each spoke account.
- Regional — Transit Gateway is a regional resource. Multi-region connectivity would require TGW
  peering between regions, which adds complexity and inter-region data transfer costs.
- Single point of failure — all cross-account traffic flows through the TGW. An AWS TGW service
  disruption would break cross-account connectivity. Mitigated by TGW being a highly available
  AWS-managed service with ENIs in multiple AZs.
- Hub account coupling — the platform account's TGW is a dependency for all spoke accounts.
  Destroying and recreating the hub TGW requires re-attaching all spokes. Mitigated by the
  platform account being the most stable environment in the topology.

**Risks:**

- If the platform VPC CIDR overlaps with a future spoke VPC, TGW routing will fail. Mitigated by
  the CIDR allocation strategy (ADR-015), which assigns non-overlapping /16 blocks per environment.
- RAM share acceptance requires the spoke account to have RAM enabled. This is automatic for
  accounts within the same AWS Organization but requires manual acceptance for external accounts.
  All current accounts are in the same organization (`o-a4kjvito7o`).
