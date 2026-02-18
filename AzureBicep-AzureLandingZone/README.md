# Azure Landing Zone - Bicep Deployment

This repository contains Bicep templates for deploying a complete Azure Landing Zone infrastructure using Azure Verified Modules (AVM) and automated CI/CD pipelines.

## Overview

This solution deploys a production-ready Azure Landing Zone with networking, security, and monitoring components, following Microsoft Cloud Adoption Framework best practices.

## Architecture

### Deployed Components

| Component | Quantity | Description |
|-----------|----------|-------------|
| Resource Groups | 6 | Organized by function with CanNotDelete locks |
| Virtual Networks | 2 | VPN network (10.190.0.0/16) + Workload network (10.200.0.0/16) |
| VPN Gateway | 1 | VpnGw1AZ SKU with availability zone support |
| Local Network Gateway | 1 | Configurable for site-to-site VPN |
| VPN Connection | 1 | IPsec/IKE site-to-site connection |
| Private DNS Zones | 6 | For Azure services (Storage, Key Vault, AVD, Backup) |
| Log Analytics Workspace | 1 | Centralized logging and monitoring |
| Public IP Address | 1 | Standard SKU for VPN Gateway |

### Resource Groups

| Name | Purpose | Lock Type |
|------|---------|-----------|
| `rsg-lz-network-01` | Networking components (VNets, VPN Gateway, NSGs) | CanNotDelete |
| `rsg-lz-platform-01` | Platform services and shared resources | CanNotDelete |
| `rsg-lz-arc-01` | Azure Arc-enabled resources | CanNotDelete |
| `rsg-lz-privateendpoint-01` | Private endpoints for Azure services | CanNotDelete |
| `rsg-lz-privatednszones-01` | Private DNS zones | CanNotDelete |
| `rsg-lz-monitoring-01` | Monitoring and logging resources | CanNotDelete |

### Network Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Azure Subscription                              │
│                                                                      │
│  ┌────────────────────────────┐  ┌───────────────────────────────┐ │
│  │ VPN Virtual Network        │  │ Workload Virtual Network      │ │
│  │ vnet-c-vpn-01       │  │ vnet-c-01              │ │
│  │ 10.190.0.0/16              │  │ 10.200.0.0/16                 │ │
│  │                            │  │                               │ │
│  │  ┌──────────────────────┐  │  │  ┌─────────────────────────┐ │ │
│  │  │ GatewaySubnet        │  │  │  │ default                 │ │ │
│  │  │ 10.190.2.0/24        │  │  │  │ 10.200.1.0/24           │ │ │
│  │  │  ┌──────────────┐    │  │  │  └─────────────────────────┘ │ │
│  │  │  │ VPN Gateway  │    │  │  │                               │ │
│  │  │  │ VpnGw1AZ     │    │  │  │  ┌─────────────────────────┐ │ │
│  │  │  └──────┬───────┘    │  │  │  │ endpoints               │ │ │
│  │  └─────────┼────────────┘  │  │  │ 10.200.2.0/24           │ │ │
│  │            │               │  │  └─────────────────────────┘ │ │
│  │  ┌─────────┴────────────┐  │  │                               │ │
│  │  │ default              │  │  │                               │ │
│  │  │ 10.190.1.0/24        │  │  └───────────────────────────────┘ │
│  │  └──────────────────────┘  │                                     │
│  └────────────┬───────────────┘                                     │
│               │                                                      │
│               │ VPN Connection (IPsec)                              │
│               │                                                      │
└───────────────┼──────────────────────────────────────────────────────┘
                │
                │ Site-to-Site VPN
                │
     ┌──────────▼──────────┐
     │  On-Premises        │
     │  Network            │
     │  (Local Network GW) │
     └─────────────────────┘
```

## Files

| File | Description |
|------|-------------|
| [deploy-azl.bicep](deploy-azl.bicep) | Main Bicep template (subscription-level deployment) |
| [deploy-azl.parameters.bicepparam](deploy-azl.parameters.bicepparam) | Parameters file with network and resource configuration |
| [DevOps Pipeline/azure-pipelines.yml](DevOps%20Pipeline/azure-pipelines.yml) | Azure DevOps CI/CD pipeline for automated deployment |
| [DevOps Pipeline/PIPELINE-SETUP.md](DevOps%20Pipeline/PIPELINE-SETUP.md) | Complete pipeline setup guide |

## Features

- ✅ Subscription-level deployment using Bicep
- ✅ Azure Verified Modules (AVM) for all resources
- ✅ Resource group locks (CanNotDelete) for production safety
- ✅ High availability VPN Gateway with availability zones
- ✅ Private DNS zones for Azure services
- ✅ Centralized logging with Log Analytics
- ✅ Automated CI/CD pipeline with approval gates
- ✅ What-If analysis before deployment
- ✅ Comprehensive validation and verification stages

## Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI or Azure PowerShell installed
- Bicep CLI (included with Azure CLI)
- On-premises VPN device configuration (for site-to-site VPN)
- Azure DevOps organization and project (for pipeline deployment)

## Deployment Options

### Option A: Azure DevOps Pipeline (Recommended)

For automated, repeatable deployments with approval gates and validation:

1. **Import the pipeline** from [DevOps Pipeline/azure-pipelines.yml](DevOps%20Pipeline/azure-pipelines.yml)
2. **Configure the environment** and service connection
3. **Set up pipeline variables** (subscription ID)
4. **Update parameters** in the bicepparam file
5. **Push to main branch** to trigger automatic deployment

**Pipeline Features**:
- ✅ Automated validation with What-If analysis
- ✅ Bicep build and syntax checking
- ✅ Subscription-level deployment validation
- ✅ Manual approval gate before deployment
- ✅ Automated verification of all resources
- ✅ Detailed deployment reporting

**See** [DevOps Pipeline/PIPELINE-SETUP.md](DevOps%20Pipeline/PIPELINE-SETUP.md) **for complete setup instructions.**

**Expected Duration**:
- Validation: 5-7 minutes
- Deployment: 45-60 minutes (VPN Gateway takes 30-45 minutes)
- Verification: 3-5 minutes

### Option B: Azure CLI

```bash
# Login to Azure
az login

# Set the subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Validate the deployment
az deployment sub validate \
  --location westeurope \
  --template-file deploy-azl.bicep \
  --parameters deploy-azl.parameters.bicepparam \
  --name landing-zone-validation

# Preview changes with What-If
az deployment sub what-if \
  --location westeurope \
  --template-file deploy-azl.bicep \
  --parameters deploy-azl.parameters.bicepparam \
  --name landing-zone-whatif

# Deploy the landing zone
az deployment sub create \
  --location westeurope \
  --template-file deploy-azl.bicep \
  --parameters deploy-azl.parameters.bicepparam \
  --name landing-zone-deployment
```

### Option C: Azure PowerShell

```powershell
# Login to Azure
Connect-AzAccount

# Set the subscription
Set-AzContext -SubscriptionId "YOUR_SUBSCRIPTION_ID"

# Validate the deployment
Test-AzDeployment `
  -Location westeurope `
  -TemplateFile "deploy-azl.bicep" `
  -TemplateParameterFile "deploy-azl.parameters.bicepparam"

# Preview changes with What-If
New-AzDeployment `
  -Location westeurope `
  -TemplateFile "deploy-azl.bicep" `
  -TemplateParameterFile "deploy-azl.parameters.bicepparam" `
  -WhatIf

# Deploy the landing zone
New-AzDeployment `
  -Name "landing-zone-deployment" `
  -Location westeurope `
  -TemplateFile "deploy-azl.bicep" `
  -TemplateParameterFile "deploy-azl.parameters.bicepparam"
```

## Configuration

### VPN Configuration

Edit [deploy-azl.parameters.bicepparam](deploy-azl.parameters.bicepparam) to configure your VPN connection:

```bicep
param localNetworkGateways = [
  {
    name: 'lng-yoursite-01'
    ipAddress: 'YOUR_ON_PREMISES_VPN_PUBLIC_IP'
    addressPrefixes: [
      'YOUR_ON_PREMISES_NETWORK_CIDR' // e.g., '172.16.0.0/16'
    ]
  }
]

param vpnConnections = [
  {
    name: 'vnet-gw-01-to-lng-yoursite-01-conn'
    vpnGatewayName: '-vnet-gw-01'
    localNetworkGatewayName: 'lng-yoursite-01'
    sharedKey: 'YOUR_SECURE_SHARED_KEY' // Use Key Vault in production!
  }
]
```

> **⚠️ Security Warning**: Never commit VPN shared keys to source control! Use Azure Key Vault for production deployments.

### Network Address Spaces

Default address spaces:

| Network | CIDR | Purpose |
|---------|------|---------|
| VPN Virtual Network | 10.190.0.0/16 | VPN Gateway and transit |
| VPN Default Subnet | 10.190.1.0/24 | General resources |
| Gateway Subnet | 10.190.2.0/24 | VPN Gateway (required) |
| Workload Virtual Network | 10.200.0.0/16 | Application workloads |
| Workload Default Subnet | 10.200.1.0/24 | VMs and resources |
| Endpoints Subnet | 10.200.2.0/24 | Private endpoints |

Modify these in the parameters file if they conflict with existing networks.

### Resource Naming Convention

All resources follow the naming pattern:

```
{prefix}-{region}-{resource-type}-{workload}-{instance}
```

Example: `vnet-c-01`
- `vnet` = Resource type
- `c` = Workload identifier (core/connectivity)
- `01` = Instance number

### Tags

Default tags applied to all resources:

```bicep
param tags = {
  Owner: 'Alex ter Neuzen'
  Department: 'GetToThe.Cloud'
  Purpose: 'Azure Landing Zone'
}
```

## Post-Deployment Configuration

### 1. Configure On-Premises VPN Device

After VPN Gateway deployment completes:

1. Get the VPN Gateway public IP:
```bash
az network public-ip show \
  --name pip-vgw-c-01 \
  --resource-group rsg-lz-network-01 \
  --query ipAddress -o tsv
```

2. Configure your on-premises VPN device with:
   - **Remote Gateway IP**: Azure VPN Gateway public IP
   - **Shared Key**: Match the key in your parameters file
   - **Remote Networks**: 10.190.0.0/16, 10.200.0.0/16
   - **Local Networks**: Your on-premises CIDR ranges

3. Verify connection status:
```bash
az network vpn-connection show \
  --name <connection-name> \
  --resource-group rsg-lz-network-01 \
  --query connectionStatus
```

### 2. Link Private DNS Zones to Virtual Networks

Private DNS zones are created but not automatically linked:

```bash
# Link DNS zone to workload virtual network
az network private-dns link vnet create \
  --resource-group rsg-lz-privatednszones-01 \
  --zone-name privatelink.file.core.windows.net \
  --name link-to-workload-vnet \
  --virtual-network vnet-c-01 \
  --registration-enabled false
```

Repeat for all DNS zones and virtual networks as needed.

### 3. Configure VNet Peering (Optional)

To enable connectivity between VPN and workload networks:

```bash
# Peer VPN network to workload network
az network vnet peering create \
  --name vpn-to-workload \
  --resource-group rsg-lz-network-01 \
  --vnet-name vnet-c-vpn-01 \
  --remote-vnet vnet-c-01 \
  --allow-vnet-access \
  --allow-forwarded-traffic \
  --allow-gateway-transit

# Peer workload network to VPN network
az network vnet peering create \
  --name workload-to-vpn \
  --resource-group rsg-lz-network-01 \
  --vnet-name vnet-c-01 \
  --remote-vnet vnet-c-vpn-01 \
  --allow-vnet-access \
  --allow-forwarded-traffic \
  --use-remote-gateways
```

### 4. Enable Diagnostic Settings

Configure diagnostic logging for VPN Gateway:

```bash
# Get Log Analytics Workspace ID
LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group rsg-lz-monitoring-01 \
  --workspace-name law-lz-01 \
  --query id -o tsv)

# Enable diagnostics for VPN Gateway
az monitor diagnostic-settings create \
  --name vpn-gateway-diagnostics \
  --resource <vpn-gateway-resource-id> \
  --workspace $LAW_ID \
  --logs '[{"category": "GatewayDiagnosticLog", "enabled": true}, {"category": "TunnelDiagnosticLog", "enabled": true}]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

## Verification

### Check Deployment Status

```bash
# List all deployments
az deployment sub list \
  --query "[?starts_with(name, 'azure-landing-zone')].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}" \
  -o table

# Show deployed resources
az deployment sub show \
  --name <deployment-name> \
  --query "properties.outputResources[].id" \
  -o table
```

### Verify VPN Gateway

```bash
# Check VPN Gateway status
az network vnet-gateway show \
  --name vnet-gw-01 \
  --resource-group rsg-lz-network-01 \
  --query "{Name:name, State:provisioningState, GatewayType:gatewayType, SKU:sku.name, ActiveActive:activeActive}" \
  -o table

# Check VPN connection status
az network vpn-connection show \
  --name <connection-name> \
  --resource-group rsg-lz-network-01 \
  --query "{Name:name, Status:connectionStatus, IngressBytes:ingressBytesTransferred, EgressBytes:egressBytesTransferred}" \
  -o table
```

### Test Connectivity

```bash
# From an Azure VM in the workload network
# Test connectivity to on-premises resource
ping <on-premises-ip>

# Test DNS resolution
nslookup <on-premises-hostname>

# Check routing table
route print (Windows) or ip route show (Linux)
```

## Troubleshooting

### VPN Gateway Takes Too Long

**Expected**: VPN Gateway deployment typically takes 30-45 minutes

**Check Status**:
```bash
az network vnet-gateway show \
  --name vnet-gw-01 \
  --resource-group rsg-lz-network-01 \
  --query provisioningState
```

### VPN Connection Not Established

**Common Issues**:
1. Shared key mismatch
2. Incorrect on-premises public IP
3. Firewall blocking IPsec traffic (UDP 500, 4500, ESP)
4. On-premises VPN device not configured

**Troubleshoot**:
```bash
# Check connection status
az network vpn-connection show \
  --name <connection-name> \
  --resource-group rsg-lz-network-01

# Reset connection
az network vpn-connection reset \
  --name <connection-name> \
  --resource-group rsg-lz-network-01
```

### Resource Locked - Cannot Delete

**Expected Behavior**: All resource groups have `CanNotDelete` locks

**Remove Lock**:
```bash
# List locks
az lock list --resource-group rsg-lz-network-01

# Delete lock (if authorized)
az lock delete \
  --name <lock-name> \
  --resource-group rsg-lz-network-01
```

## Cost Estimation

### Monthly Costs (West Europe Region)

| Resource | Configuration | Estimated Cost |
|----------|---------------|----------------|
| VPN Gateway | VpnGw1AZ | ~€125/month |
| Public IP Address | Standard SKU | ~€4/month |
| Virtual Networks | 2 VNets | Free |
| Resource Groups | 6 groups | Free |
| Private DNS Zones | 6 zones | ~€3/month |
| Log Analytics Workspace | 5GB/month ingestion | ~€10/month |
| **Total** | | **~€142/month** |

> **Note**: Costs may vary based on actual usage, data transfer, and log ingestion volumes.

## Azure Verified Modules

This template leverages certified Azure Verified Modules (AVM):

| Module | Version | Purpose |
|--------|---------|---------|
| `avm/res/resources/resource-group` | 0.4.3 | Resource group management |
| `avm/res/network/virtual-network` | 0.7.2 | Virtual network deployment |
| `avm/res/network/virtual-network-gateway` | 0.10.1 | VPN Gateway deployment |
| `avm/res/network/local-network-gateway` | 0.4.0 | Local network gateway |
| `avm/res/network/connection` | 0.1.6 | VPN connection |
| `avm/res/network/public-ip-address` | 0.5.1 | Public IP addresses |
| `avm/res/network/private-dns-zone` | 0.5.0 | Private DNS zones |
| `avm/res/operational-insights/workspace` | 0.15.0 | Log Analytics workspace |

**Benefits**:
- ✅ Microsoft-validated and supported
- ✅ Best practices built-in
- ✅ Regular updates and security patches
- ✅ Consistent parameter schemas

Learn more: [aka.ms/avm](https://aka.ms/avm)

## Related Resources

- [Azure Landing Zones](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- [Azure VPN Gateway Documentation](https://learn.microsoft.com/azure/vpn-gateway/)
- [Configure Site-to-Site VPN](https://learn.microsoft.com/azure/vpn-gateway/tutorial-site-to-site-portal)
- [Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-overview)
- [Azure Verified Modules](https://aka.ms/avm)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## Contributing

Found an issue or have a suggestion? Visit [GetToThe.Cloud](https://www.gettothe.cloud) or open an issue on GitHub.

## License

This template is provided as-is under the MIT License.

---

**Author**: Alex ter Neuzen  
**Website**: [GetToThe.Cloud](https://www.gettothe.cloud)  
**Last Updated**: February 2026
