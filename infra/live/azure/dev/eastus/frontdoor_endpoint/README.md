# Azure Front Door Endpoint - East US (Dev)

## Overview

This directory contains the Terragrunt configuration for deploying and managing Azure Front Door Endpoint in the East US region for the development environment. The endpoint provides the entry point for global content delivery and application acceleration through the Azure Front Door service.

## Configuration Details

### Purpose

This configuration:
- Creates a Front Door endpoint that serves as the entry point for client requests
- Configures origin groups for backend service routing
- Establishes health probes to ensure backend service availability
- Implements load balancing for traffic distribution across origins
- Enables global content delivery with caching capabilities

### Dependencies

This configuration depends on:
- **naming**: Uses standardized resource naming conventions
- **frontdoor_profile**: References the parent Front Door profile

### Key Configuration Settings

- **Endpoint Configuration**:
  - Name: Following naming convention from the naming module
  - Associated with the Front Door profile

- **Origin Group Configuration**:
  - Load Balancing: Enabled with sample size of 4 and 2 successful samples required
  - Additional Latency: 50ms allowable additional latency
  - Health Probes: HTTPS probes configured with 30-second intervals
  - Path: "/health" endpoint for health checks
  - Request Type: GET

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/dev/eastus/frontdoor_endpoint
terragrunt plan
terragrunt apply
```

To view the endpoint URL after deployment:

```bash
cd infra/live/azure/dev/eastus/frontdoor_endpoint
terragrunt output endpoint_url
```

## Dependencies on this Configuration

The following modules depend on outputs from this configuration:
- frontdoor_private_link (uses the endpoint and origin group IDs)
- Any module that needs to reference the Front Door endpoint

## Implementation Notes

The Front Door endpoint provides the globally accessible URL for your application. The health probes are configured to verify backend availability before routing traffic. The load balancing settings can be adjusted based on your application's specific requirements and backend response characteristics.

In a production environment, consider implementing additional security settings like WAF policies and custom domains with HTTPS enforcement. Also, ensure proper cache configurations are in place for optimal performance. 