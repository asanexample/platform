# Diagram Guidelines

This directory contains diagram files for the VIP Platform documentation. The diagrams should be created using [draw.io](https://draw.io) and exported in both source format (.drawio) and PNG format for embedding in documentation.

## Required Diagrams

The following diagrams should be created for the documentation:

1. **Logical Architecture** - `logical-architecture.png`
   - Shows the logical layers of the VIP Platform
   - Include foundation, service, application, security, and operations layers

2. **Physical Architecture** - `physical-architecture.png`
   - Shows the physical implementation across cloud providers, regions, and environments
   - Include connectivity between components

3. **CIDR Allocation Hierarchy** - `cidr-allocation-hierarchy.png`
   - Visualizes the hierarchical CIDR allocation strategy
   - Shows cloud provider, environment, region, availability zone, and subnet levels

4. **Kubernetes Network Topology** - `kubernetes-network-topology.png`
   - Shows the network design for Kubernetes clusters
   - Include all subnet types and their relationships

5. **Terraform Module Architecture** - `terraform-module-architecture.png`
   - Shows the relationships between Terraform modules
   - Include dependencies and component structure

6. **Network Architecture** - `network-architecture.png`
   - Shows the overall network topology of the platform
   - Include connectivity between regions and environments

7. **Deployment Architecture** - `deployment-architecture.png`
   - Shows the Terragrunt deployment flow
   - Include the CI/CD pipeline integration

## Design Guidelines

When creating diagrams:

1. Use a consistent color scheme:
   - AWS: Orange
   - Azure: Blue
   - GCP: Green
   - Cross-cloud: Purple

2. Use appropriate shapes:
   - Infrastructure components: Rectangles
   - Networks: Cloud shapes or hexagons
   - Connectivity: Solid lines for direct connections, dashed for indirect

3. Include a legend to explain symbols

4. Keep diagrams simple and focused on the key message

5. Use hierarchical layout for most diagrams

6. Save source files (.drawio) alongside PNG exports

## Example Diagram Structure

A typical diagram structure might include:

- Top-level components (cloud providers)
- Second-level components (regions/environments)
- Third-level components (services)
- Connectivity between components
- Clear labeling of each component
- Legend explaining symbols and colors
