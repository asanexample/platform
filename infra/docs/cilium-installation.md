# Cilium Installation Guide for AKS

This guide details the process for installing and configuring Cilium CNI on Azure Kubernetes Service (AKS) clusters that are deployed without any default CNI.

## Prerequisites

- AKS cluster provisioned with `network_plugin = "none"` and `network_policy = null`
- `kubectl` configured to connect to the AKS cluster
- `helm` v3.x installed
- Administrative access to the AKS cluster

## Installation Process

### 1. Verify Cluster Configuration

Before installing Cilium, verify that your AKS cluster is properly configured without any CNI:

```bash
az aks show --resource-group <resource-group-name> --name <cluster-name> --query networkProfile
```

Confirm that the output shows:
```json
{
  "networkPlugin": "none",
  "networkPolicy": null,
  ...
}
```

### 2. Install the Cilium CLI (Optional but Recommended)

The Cilium CLI simplifies installation, verification, and troubleshooting:

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz
```

### 3. Add the Cilium Helm Repository

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
```

### 4. Install Cilium via Helm

For a standard installation:

```bash
helm install cilium cilium/cilium \
  --version 1.14.2 \
  --namespace kube-system \
  --set azure.enabled=true \
  --set azure.resourceGroup=<resource-group-name> \
  --set azure.subscriptionID=<subscription-id> \
  --set azure.tenantID=<tenant-id> \
  --set azure.userAssignedIdentity=<identity-client-id> \
  --set ipam.mode=kubernetes \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
```

For production deployments, create a values file with your customizations:

```yaml
# cilium-values.yaml
azure:
  enabled: true
  resourceGroup: <resource-group-name>
  subscriptionID: <subscription-id>
  tenantID: <tenant-id>
  userAssignedIdentity: <identity-client-id>

ipam:
  mode: kubernetes

hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true

nodePort:
  enabled: true

kubeProxyReplacement: "strict"
k8sServiceHost: <aks-apiserver-hostname>
k8sServicePort: 443

# Enable WireGuard for encryption (optional)
encryption:
  enabled: true
  type: wireguard

# Resources for Cilium agent
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 512Mi
```

Then install with:

```bash
helm install cilium cilium/cilium \
  --version 1.14.2 \
  --namespace kube-system \
  -f cilium-values.yaml
```

### 5. Verify Installation

Using the Cilium CLI:

```bash
cilium status --wait
```

or using kubectl:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

All Cilium pods should be in Running state. You can verify Cilium connectivity with:

```bash
kubectl create ns cilium-test
cilium connectivity test --namespace cilium-test
```

### 6. Install Hubble UI for Network Visibility (Optional)

If you've enabled Hubble in your installation, port-forward to access the UI:

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

Then access the UI at: http://localhost:12000

## Advanced Configuration Options

### Multi-Pool or Custom IPAM

For custom IP allocation:

```yaml
ipam:
  mode: kubernetes
  operator:
    clusterPoolIPv4PodCIDRList: ["10.10.0.0/16"]
```

### Transparent Encryption with WireGuard

Enable transparent encryption between pods:

```yaml
encryption:
  enabled: true
  type: wireguard
```

### Enhanced Network Policies

Cilium supports enhanced network policies beyond Kubernetes standard:

```yaml
# example-cilium-network-policy.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: app-layer-policy
spec:
  endpointSelector:
    matchLabels:
      app: myapp
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/api/v1/users"
```

Apply with:

```bash
kubectl apply -f example-cilium-network-policy.yaml
```

## Troubleshooting

### Check Cilium Agent Status

```bash
cilium status
```

### View Cilium Agent Logs

```bash
kubectl logs -n kube-system -l k8s-app=cilium --tail=100
```

### Verify Node-to-Node Connectivity

```bash
cilium connectivity test
```

### Debug Network Policies

```bash
cilium policy get
```

### Check eBPF Maps

```bash
cilium bpf policy get
```

### Common Issues

1. **Pods Stuck in Pending State**:
   - Check if Cilium agent is running properly
   - Ensure CNI configuration is correct
   - Verify IPAM allocation

2. **Node-to-Node Communication Issues**:
   - Verify NSG rules allow communication between nodes on required ports
   - Check if the Azure identity has proper permissions

3. **Service Connectivity Problems**:
   - Ensure kube-proxy replacement mode is properly configured
   - Check if appropriate service CIDRs are configured

4. **API Server Connectivity**:
   - Ensure `k8sServiceHost` is properly set to the AKS API server hostname

## Cleanup

To uninstall Cilium:

```bash
helm uninstall cilium -n kube-system
```

Note: Removing Cilium without another CNI in place will break pod networking. Only do this if you plan to install a different CNI immediately.

## References

- [Cilium Documentation](https://docs.cilium.io/)
- [Cilium AKS Guide](https://docs.cilium.io/en/stable/installation/k8s-install-azure/)
- [Cilium Network Policies](https://docs.cilium.io/en/stable/network/networkpolicy/)
- [Hubble Documentation](https://docs.cilium.io/en/stable/network/hubble/)
- [Cilium CLI Reference](https://docs.cilium.io/en/stable/cmdref/cilium/) 