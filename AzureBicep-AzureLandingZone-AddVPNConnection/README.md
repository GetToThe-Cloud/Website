# Add VPN Connections to Azure Landing Zone

[![Bicep Version](https://img.shields.io/badge/Bicep-Latest-blue)](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
[![Azure Verified Modules](https://img.shields.io/badge/AVM-Enabled-green)](https://aka.ms/avm)

Incrementally deploy Site-to-Site VPN connections to an existing Azure VPN Gateway without disrupting current infrastructure.

## Overview

This Bicep template allows you to add new VPN connections to your Azure landing zone by deploying:

- **Local Network Gateways** - Representing remote sites (on-premises, branch offices, partner networks)
- **VPN Connections** - IPsec tunnels connecting Azure to remote locations
- **Incremental deployment** - Adds connections without affecting existing infrastructure

Perfect for organizations expanding their hybrid connectivity or adding new site-to-site VPN tunnels.

## Prerequisites

Before deploying, ensure you have:

- ✅ An existing **Azure VPN Gateway** (already deployed in your landing zone)
- ✅ **Resource Group** where the VPN Gateway resides
- ✅ **Contributor** or **Network Contributor** permissions on the resource group
- ✅ Remote site information:
  - Public IP address of the remote VPN device
  - Network address ranges (CIDR) of the remote networks
  - IPsec pre-shared key (PSK)

## Features

- 🚀 **Azure Verified Modules** - Uses certified AVM modules for reliability
- 🔒 **Secure by design** - Supports Azure Key Vault for secret management
- 📦 **Incremental deployment** - Only deploys what you need
- 🔄 **Multiple connections** - Deploy multiple VPN tunnels in one operation
- 🏷️ **Tagging support** - Apply consistent tags to all resources
- 📊 **Comprehensive outputs** - Returns resource IDs and names for automation

## Deployment Options

### Option A: Azure DevOps Pipeline (Recommended)

For automated, repeatable deployments with validation and approval gates:

1. **Import Pipeline**: See [PIPELINE-SETUP.md](PIPELINE-SETUP.md) for detailed instructions
2. **Configure Variables**: Update service connection and resource group names
3. **Run Pipeline**: Automatic validation, deployment, and verification

Benefits:
- ✅ Automated validation with What-If analysis
- ✅ Environment approval gates for production
- ✅ Comprehensive verification and reporting
- ✅ Deployment artifacts and history
- ✅ Integration with Azure DevOps work items

### Option B: Manual Deployment

For quick, one-time deployments:

## Quick Start

### 1. Configure Parameters

Edit the `azurebicep-azurelandingzone-addvpnconnection.parameters.bicepparam` file:

```bicep
param virtualNetworkGatewayName = 'your-vpn-gateway-name'

param localNetworkGateways = [
  {
    name: 'lng-branch-office-01'
    ipAddress: '203.0.113.10'              // Remote VPN device public IP
    addressPrefixes: [
      '10.100.0.0/16'                      // Remote network ranges
    ]
  }
]

param vpnConnections = [
  {
    name: 'connection-branch-office-01'
    sharedKey: 'your-secure-preshared-key' // Match this on remote device
  }
]
```

## Deployment Options

See detailed pipeline setup guide: **[PIPELINE-SETUP.md](PIPELINE-SETUP.md)**

### Option A: Azure DevOps Pipeline (Recommended)

Automated deployment with validation and approval gates.

```bash
# Import pipeline
az pipelines create \
  --name "Deploy VPN Connections" \
  --repository GetToTheCloud/Website \
  --branch main \
  --yml-path AzureBicep-AzureLandingZone-AddVPNConnection/azure-pipelines.yml
```

**Pipeline Features:**
- Bicep build and validation
- What-If deployment analysis  
- VPN Gateway verification
- Automated deployment
- Connection status verification
- Deployment reports

**Runtime**: ~15-20 minutes total

### Option B: Azure CLI

Direct deployment from command line.

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Deploy to resource group
az deployment group create \
  --resource-group "your-resource-group" \
  --template-file azurebicep-azurelandingzone-addvpnconnection.bicep \
  --parameters azurebicep-azurelandingzone-addvpnconnection.parameters.bicepparam
```

### Option C: PowerShell

```powershell
# Connect to Azure
Connect-AzAccount

# Set context
Set-AzContext -Subscription "your-subscription-id"

# Deploy
New-AzResourceGroupDeployment `
  -ResourceGroupName "your-resource-group" `
  -TemplateFile azurebicep-azurelandingzone-addvpnconnection.bicep `
  -TemplateParameterFile azurebicep-azurelandingzone-addvpnconnection.parameters.bicepparam
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `localNetworkGateways` | array | Yes | Array of local network gateways to create |
| `vpnConnections` | array | Yes | Array of VPN connections to establish |
| `virtualNetworkGatewayName` | string | Yes | Name of the existing VPN Gateway |
| `tags` | object | No | Tags to apply to all resources |
| `location` | string | No | Azure region (defaults to resource group location) |

### Local Network Gateway Object Structure

```bicep
{
  name: 'string'              // Name for the Local Network Gateway
  ipAddress: 'string'         // Public IP of remote VPN device
  addressPrefixes: [          // Remote network address spaces
    'string'                  // e.g., '10.0.0.0/16'
  ]
}
```

### VPN Connection Object Structure

```bicep
{
  name: 'string'              // Name for the VPN connection
  sharedKey: 'string'         // IPsec pre-shared key (PSK)
}
```

> **Note**: Connection array indexes must match Local Network Gateway array indexes.  
> `vpnConnections[0]` connects to `localNetworkGateways[0]`, etc.

## Examples

### Single VPN Connection

```bicep
param virtualNetworkGatewayName = 'vnet-gw-prod-01'

param localNetworkGateways = [
  {
    name: 'lng-datacenter-01'
    ipAddress: '203.0.113.50'
    addressPrefixes: ['10.200.0.0/16', '172.16.0.0/12']
  }
]

param vpnConnections = [
  {
    name: 'conn-datacenter-01'
    sharedKey: 'SuperSecureKey123!'
  }
]
```

### Multiple VPN Connections

```bicep
param virtualNetworkGatewayName = 'vnet-gw-prod-01'

param localNetworkGateways = [
  {
    name: 'lng-hq-01'
    ipAddress: '203.0.113.10'
    addressPrefixes: ['10.10.0.0/16']
  },
  {
    name: 'lng-branch-01'
    ipAddress: '203.0.113.20'
    addressPrefixes: ['10.20.0.0/16']
  },
  {
    name: 'lng-partner-01'
    ipAddress: '203.0.113.30'
    addressPrefixes: ['10.30.0.0/16']
  }
]

param vpnConnections = [
  {
    name: 'conn-hq-01'
    sharedKey: 'HQSecureKey123!'
  },
  {
    name: 'conn-branch-01'
    sharedKey: 'BranchSecureKey123!'
  },
  {
    name: 'conn-partner-01'
    sharedKey: 'PartnerSecureKey123!'
  }
]
```

### With Custom Tags

```bicep
param tags = {
  Environment: 'Production'
  CostCenter: 'IT-Network'
  Owner: 'network-team@company.com'
  Project: 'Hybrid-Connectivity'
}
```

## Outputs

The template provides the following outputs for use in automation or subsequent deployments:

| Output | Type | Description |
|--------|------|-------------|
| `localNetworkGatewayResourceIds` | array | Resource IDs of created Local Network Gateways |
| `localNetworkGatewayNames` | array | Names of created Local Network Gateways |
| `connectionResourceIds` | array | Resource IDs of created VPN Connections |
| `connectionNames` | array | Names of created VPN Connections |
| `vpnGatewayResourceId` | string | Resource ID of the existing VPN Gateway |
| `vpnGatewayName` | string | Name of the existing VPN Gateway |

### Using Outputs in Pipeline

```yaml
- task: AzureCLI@2
  inputs:
    scriptType: bash
    inlineScript: |
      connectionIds=$(az deployment group show \
        --resource-group ${{ parameters.resourceGroup }} \
        --name vpn-deployment \
        --query 'properties.outputs.connectionResourceIds.value' -o tsv)
      echo "Created connections: $connectionIds"
```

## Security Best Practices

### 1. Use Azure Key Vault for Shared Keys

Instead of storing pre-shared keys in parameter files:

```bicep
@secure()
param sharedKey string

// In parameter file, use Key Vault reference:
// sharedKey: az.keyVault('your-vault', 'vpn-psk-secret')
```

### 2. Protect Parameter Files

- ❌ **Never commit shared keys to source control**
- ✅ Store sensitive parameters in Azure Key Vault
- ✅ Use pipeline secret variables
- ✅ Implement proper `.gitignore` rules

### 3. Key Rotation

```bash
# Update the shared key for an existing connection
az network vpn-connection shared-key update \
  --resource-group "your-rg" \
  --connection-name "your-connection" \
  --value "NewSecureKey456!"
```

## Troubleshooting

### Connection Shows "NotConnected"

**Causes**:
1. Shared key mismatch between Azure and remote device
2. Remote VPN device not configured
3. Firewall blocking IPsec traffic (UDP 500, 4500, ESP)
4. Incorrect remote IP or network ranges

**Solution**:
```bash
# Verify connection status
az network vpn-connection show \
  --resource-group "your-rg" \
  --name "your-connection" \
  --query '{Status:connectionStatus, State:provisioningState}'

# Check shared key
az network vpn-connection shared-key show \
  --resource-group "your-rg" \
  --connection-name "your-connection"

# Force reconnection
az network vpn-connection update \
  --resource-group "your-rg" \
  --name "your-connection" \
  --force
```

### Deployment Fails - VPN Gateway Not Found

**Error**: `Resource 'vnet-gw-prod-01' not found`

**Solution**: Verify the VPN Gateway exists and the name is correct:

```bash
# List VPN Gateways in resource group
az network vnet-gateway list \
  --resource-group "your-rg" \
  --output table
```

### Template Validation Errors

```bash
# Build and validate Bicep template
az bicep build --file azurebicep-azurelandingzone-addvpnconnection.bicep

# Perform validation before deployment
az deployment group validate \
  --resource-group "your-rg" \
  --template-file azurebicep-azurelandingzone-addvpnconnection.bicep \
  --parameters azurebicep-azurelandingzone-addvpnconnection.parameters.bicepparam
```

## Verification

After deployment, verify your VPN connections:

### Azure Portal
1. Navigate to your VPN Gateway
2. Click **Connections** under Settings
3. Check connection status (should show "Connected")

### Azure CLI
```bash
# List all connections
az network vpn-connection list \
  --resource-group "your-rg" \
  --output table

# Get detailed connection metrics
az network vpn-connection show \
  --resource-group "your-rg" \
  --name "your-connection"
```

### Connection Test
```bash
# Test connectivity from Azure VM to remote network
ping 10.100.0.1  # Replace with IP in remote network

# Traceroute to verify VPN path
traceroute 10.100.0.1
```

## Architecture

```
┌─────────────────────────────────────────────┐
│  Azure Landing Zone                          │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │ Resource Group                          │ │
│  │                                         │ │
│  │  ┌──────────────────────────┐          │ │
│  │  │ VPN Gateway (Existing)   │          │ │
│  │  │ Type: VPN                │          │ │
│  │  └──────────┬───────────────┘          │ │
│  │             │                           │ │
│  │    ┌────────┴────────┐                 │ │
│  │    │                 │                 │ │
│  │  ┌─▼──────────┐   ┌─▼──────────┐      │ │
│  │  │ Connection │   │ Connection │      │ │
│  │  │    (New)   │   │    (New)   │      │ │
│  │  └─┬──────────┘   └─┬──────────┘      │ │
│  │    │                │                  │ │
│  │  ┌─▼──────────┐   ┌─▼──────────┐      │ │
│  │  │    LNG     │   │    LNG     │      │ │
│  │  │  (New)     │   │  (New)     │      │ │
│  │  └─┬──────────┘   └─┬──────────┘      │ │
│  └────┼──────────────┼──────────────────┘ │
└───────┼──────────────┼────────────────────┘
        │              │
       VPN            VPN
        │              │
   ┌────▼─────┐   ┌───▼──────┐
   │ Remote   │   │ Remote   │
   │ Site 1   │   │ Site 2   │
   └──────────┘   └──────────┘
```

## Cost Considerations

This template **does not create a VPN Gateway** (uses existing), so costs are minimal:

| Resource | Estimated Cost (West Europe) |
|----------|------------------------------|
| Local Network Gateway | Free |
| VPN Connection | Included with VPN Gateway |
| Data Transfer | ~€0.01 per GB (egress) |

> **Note**: VPN Gateway costs continue as normal (~€100-400/month depending on SKU).

## Azure Verified Modules

This template leverages certified Azure Verified Modules (AVM):

- **Local Network Gateway**: `avm/res/network/local-network-gateway:0.4.0`
- **VPN Connection**: `avm/res/network/connection:0.1.6`

Benefits of using AVM:
- ✅ Microsoft-validated and supported
- ✅ Best practices built-in
- ✅ Regular updates and security patches
- ✅ Consistent parameter schemas

Learn more: [aka.ms/avm](https://aka.ms/avm)

## Related Resources

- [Azure VPN Gateway Documentation](https://learn.microsoft.com/azure/vpn-gateway/)
- [Configure Site-to-Site VPN](https://learn.microsoft.com/azure/vpn-gateway/tutorial-site-to-site-portal)
- [VPN Gateway Design](https://learn.microsoft.com/azure/vpn-gateway/design)
- [IPsec/IKE Parameters](https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpn-devices)
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

