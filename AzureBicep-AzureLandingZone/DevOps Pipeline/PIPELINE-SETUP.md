# Azure DevOps Pipeline Setup Guide
## Azure Landing Zone Deployment

This guide walks you through setting up the Azure DevOps pipeline for automated deployment of an Azure Landing Zone using Bicep and Azure Resource Manager.

---

## Overview

This pipeline deploys a complete Azure Landing Zone infrastructure including:

- **6 Resource Groups** with CanNotDelete locks
- **2 Virtual Networks** with subnets (VPN network + workload network)
- **VPN Gateway** (VpnGw1AZ SKU) with high availability
- **Local Network Gateway** for site-to-site VPN
- **VPN Connection** with IPsec/IKE configuration
- **6 Private DNS Zones** for Azure services
- **Log Analytics Workspace** with diagnostic settings
- **Public IP Address** (Standard SKU) for VPN Gateway

---

## Prerequisites

### 1. Azure Service Connection

1. Go to **Project Settings** → **Service connections**
2. Click **New service connection** → **Azure Resource Manager**
3. Select **Service principal (automatic)**
4. Configure the connection:
   - **Subscription**: Select your Azure subscription
   - **Resource group**: Leave empty (subscription-level deployment)
   - **Service connection name**: `Azure-ServiceConnection`
   - **Grant access permission to all pipelines**: ☑️ Enabled
5. Click **Save**

> **Important**: The service principal needs **Owner** or **Contributor** role at **subscription level** for this deployment.

### 2. Pipeline Variables

Configure the following pipeline variable:

1. Go to **Pipelines** → Select your pipeline → **Edit** → **Variables**
2. Add the following variable:

| Variable Name | Value | Secret | Description |
|---------------|-------|--------|-------------|
| `ARM_SUBSCRIPTION_ID` | Your Azure subscription ID | ☐ No | The subscription where resources will be deployed |

### 3. Azure DevOps Environment

Create an environment for deployment approvals:

1. Go to **Pipelines** → **Environments**
2. Click **New environment**
3. Configure:
   - **Name**: `production-landing-zone`
   - **Description**: "Production Azure Landing Zone environment"
   - **Resource**: None
4. Click **Create**
5. Add **Approvals**:
   - Click on the environment → **⋯** → **Approvals and checks**
   - Add **Approvals** → Select 2+ approvers (recommended)
   - Configure approval policy
   - **Timeout**: 48 hours (recommended)

### 4. Azure Subscription Prerequisites

Ensure your Azure subscription has:
- ✅ Sufficient quota for VPN Gateway (VpnGw1AZ requires availability zones)
- ✅ Permissions to create resource groups at subscription level
- ✅ No conflicting IP address ranges (10.190.0.0/16, 10.200.0.0/16)
- ✅ No existing resources with the same names

---

## Pipeline Setup

### 1. Import Pipeline

1. **Pipelines** → **New pipeline**
2. Select **Azure Repos Git** (or your repository location)
3. Select your repository
4. Choose **Existing Azure Pipelines YAML file**
5. Select: `/AzureBicep-AzureLandingZone/DevOps Pipeline/azure-pipelines.yml`
6. Click **Continue**

### 2. Update Pipeline Variables

Before saving, update these variables in the YAML:

```yaml
variables:
  - name: serviceConnection
    value: 'Azure-ServiceConnection' # Your service connection name
  - name: deploymentLocation
    value: 'westeurope' # Your preferred Azure region
```

### 3. Save and Run

1. Click **Save** (not "Save and run" yet)
2. Review the pipeline configuration
3. Click **Run pipeline** to trigger first deployment

---

## Pipeline Stages

### Stage 1: Validate (5-7 minutes)

**Automatic - No approval required**

- ✅ Bicep CLI installation and upgrade
- ✅ Bicep template build and syntax check
- ✅ Parameters file validation
- ✅ Azure subscription deployment validation
- ✅ What-If analysis preview
- ✅ Existing resources check
- ✅ Artifact publishing

**What to Review**:
- Check What-If analysis output for unexpected changes
- Verify no conflicting resources will be deleted
- Review resource counts and naming

### Stage 2: Deploy (45-60 minutes)

**Manual approval required from `production-landing-zone` environment**

- 🚀 Deploy resource groups with locks
- 🚀 Deploy virtual networks and subnets
- 🚀 Deploy VPN Gateway (⚠️ takes 30-45 minutes)
- 🚀 Deploy local network gateway
- 🚀 Deploy VPN connection
- 🚀 Deploy private DNS zones
- 🚀 Deploy Log Analytics workspace
- 🚀 Deploy public IP address
- 📊 Parse deployment outputs

**Approval Checklist**:
- ☑️ What-If analysis reviewed and approved
- ☑️ VPN shared key is securely stored
- ☑️ On-premises VPN device configuration is ready
- ☑️ IP address ranges don't conflict with existing networks
- ☑️ Change window is appropriate for 45+ minute deployment

### Stage 3: Verify (3-5 minutes)

**Automatic after deployment**

- ✔️ Verify resource groups and locks
- ✔️ Verify virtual networks and subnets
- ✔️ Verify VPN Gateway provisioning status
- ✔️ Verify local network gateway
- ✔️ Verify VPN connections
- ✔️ Verify private DNS zones
- ✔️ Verify Log Analytics workspace
- 📄 Generate deployment report

---

## Configuration

### Update Parameters

Edit [deploy-azl.parameters.bicepparam](../deploy-azl.parameters.bicepparam):

#### VPN Configuration

```bicep
param localNetworkGateways = [
  {
    name: '${prefix}-${region}-lng-yoursite-01'
    ipAddress: 'YOUR_ON_PREM_VPN_PUBLIC_IP' // Update this
    addressPrefixes: [
      'YOUR_ON_PREM_NETWORK_CIDR' // e.g., '172.16.0.0/16'
    ]
  }
]

param vpnConnections = [
  {
    name: '${prefix}-${region}-vnet-gw-01-to-${localNetworkGateways[0].name}-conn'
    vpnGatewayName: '${prefix}-${region}-vnet-gw-01'
    localNetworkGatewayName: '${prefix}-${region}-lng-yoursite-01'
    sharedKey: 'YOUR_SECURE_SHARED_KEY' // Store in Key Vault!
  }
]
```

> **Security Warning**: Never commit VPN shared keys to source control in production! Use Azure Key Vault references.

#### Network Configuration

```bicep
param virtualNetworks = [
  {
    name: '${prefix}-${region}-vnet-c-vpn-01'
    addressPrefixes: ['10.190.0.0/16']
    subnets: [
      {
        name: 'default'
        addressPrefix: '10.190.1.0/24'
      }
      {
        name: 'GatewaySubnet' // Required name for VPN Gateway
        addressPrefix: '10.190.2.0/24' // Min /27, recommended /24
      }
    ]
    tags: tags
  }
]
```

#### Private DNS Zones

```bicep
param dnsZones = [
  { name: 'privatelink.vaultcore.azure.net', tags: tags }
  { name: 'privatelink.file.core.windows.net', tags: tags }
  { name: 'privatelink.blob.core.windows.net', tags: tags }
  { name: 'privatelink.queue.core.windows.net', tags: tags }
  { name: 'privatelink.we.backup.windowsazure.com', tags: tags }
  { name: 'privatelink.wvd.microsoft.com', tags: tags }
]
```

---

## Running the Pipeline

### Automatic Trigger

The pipeline automatically triggers when:
- Code is pushed to `main` branch
- Files in `AzureBicep-AzureLandingZone/` are modified

### Manual Trigger

1. Go to **Pipelines** → Select your pipeline
2. Click **Run pipeline**
3. Select branch (default: `main`)
4. Click **Run**

### Monitoring Deployment

#### Stage 1: Validate
1. Monitor Bicep build and validation
2. **Review What-If analysis carefully**
3. Check for any validation errors
4. Pipeline proceeds automatically if validation succeeds

#### Stage 2: Deploy
1. Pipeline pauses for manual approval
2. Review validation results from Stage 1
3. **Approve deployment** in environment
4. Monitor deployment progress
   - ⏱️ Resource Groups: 1-2 minutes
   - ⏱️ Virtual Networks: 2-3 minutes
   - ⏱️ VPN Gateway: **30-45 minutes** ⚠️
   - ⏱️ Other resources: 5-10 minutes

#### Stage 3: Verify
1. Runs automatically after deployment
2. Reviews all deployed resources
3. Checks provisioning states
4. Generates deployment report

---

## Troubleshooting

### Issue: "Deployment validation failed"

**Causes**:
- Insufficient permissions (need Contributor or Owner at subscription level)
- Conflicting IP address ranges
- Resource name conflicts
- Quota limitations for VPN Gateway

**Solution**:
```bash
# Check your role assignments
az role assignment list --assignee <your-user-or-sp-id> --scope /subscriptions/<subscription-id>

# Check for conflicting resources
az network vnet list --query "[?contains(addressSpace.addressPrefixes[0], '10.190') || contains(addressSpace.addressPrefixes[0], '10.200')].{Name:name, AddressSpace:addressSpace.addressPrefixes[0]}"

# Check VPN Gateway quota
az vm list-usage --location westeurope --query "[?localName=='Virtual Network Gateways']"
```

### Issue: "VPN Gateway provisioning timeout"

**Causes**:
- VPN Gateway deployment takes 30-45 minutes
- Regional capacity issues
- Availability zone requirements not met

**Solution**:
- Increase pipeline timeout settings
- Check Azure status page for regional issues
- Verify availability zones are supported in your region
- Consider using non-AZ SKU (VpnGw1 instead of VpnGw1AZ) for testing

### Issue: "VPN Connection not established"

**Causes**:
1. Shared key mismatch between Azure and on-premises device
2. Incorrect on-premises public IP address
3. Firewall blocking IPsec traffic (UDP 500, 4500, ESP protocol 50)
4. Incompatible IPsec/IKE parameters

**Solution**:
```bash
# Check VPN connection status
az network vpn-connection show \
  --name <connection-name> \
  --resource-group azl-we-rsg-lz-network-01 \
  --query "{Name:name, Status:connectionStatus, IngressBytes:ingressBytesTransferred, EgressBytes:egressBytesTransferred}"

# Show VPN connection details
az network vpn-connection show \
  --name <connection-name> \
  --resource-group azl-we-rsg-lz-network-01

# Reset VPN connection
az network vpn-connection reset \
  --name <connection-name> \
  --resource-group azl-we-rsg-lz-network-01
```

### Issue: "Resource group locked - cannot delete/modify"

**Expected Behavior**: All resource groups have `CanNotDelete` locks

**Solution**:
```bash
# List locks
az lock list --resource-group azl-we-rsg-lz-network-01

# Remove lock (if needed)
az lock delete --name <lock-name> --resource-group <resource-group-name>

# Perform operations

# Re-apply lock
az lock create --name <lock-name> --resource-group <resource-group-name> --lock-type CanNotDelete
```

### Issue: "Private DNS zone not linked to VNet"

**Note**: This template creates DNS zones but doesn't auto-link them to VNets

**Solution**:
```bash
# Link DNS zone to virtual network
az network private-dns link vnet create \
  --resource-group azl-we-rsg-lz-privatednszones-01 \
  --zone-name privatelink.file.core.windows.net \
  --name <link-name> \
  --virtual-network <vnet-resource-id> \
  --registration-enabled false
```

---

## Advanced Configuration

### Environment-Specific Parameters

Create environment-specific parameter files:

```yaml
# Directory structure
AzureBicep-AzureLandingZone/
├── deploy-azl.bicep
├── deploy-azl.parameters.dev.bicepparam
├── deploy-azl.parameters.test.bicepparam
├── deploy-azl.parameters.prod.bicepparam
```

Update pipeline to use environment parameter:

```yaml
variables:
  - name: bicepParameters
    value: 'deploy-azl.parameters.$(Environment).bicepparam'
```

### Secure Shared Key with Key Vault

Instead of hardcoding VPN shared keys:

1. **Store in Key Vault**:
```bash
az keyvault secret set \
  --vault-name <your-keyvault> \
  --name vpn-shared-key \
  --value "YOUR_SECURE_KEY"
```

2. **Reference in Bicep**:
```bicep
param vpnSharedKey string = keyVault.getSecret('vpn-shared-key')
```

3. **Grant pipeline access**:
```bash
az keyvault set-policy \
  --name <your-keyvault> \
  --spn <service-principal-id> \
  --secret-permissions get list
```

### Multiple VPN Connections

Add multiple sites to the parameters:

```bicep
param localNetworkGateways = [
  {
    name: '${prefix}-${region}-lng-site1-01'
    ipAddress: 'SITE1_PUBLIC_IP'
    addressPrefixes: ['172.16.0.0/16']
  }
  {
    name: '${prefix}-${region}-lng-site2-01'
    ipAddress: 'SITE2_PUBLIC_IP'
    addressPrefixes: ['172.17.0.0/16']
  }
]

param vpnConnections = [
  {
    name: 'connection-to-site1'
    vpnGatewayName: '${prefix}-${region}-vnet-gw-01'
    localNetworkGatewayName: '${prefix}-${region}-lng-site1-01'
    sharedKey: '<key-from-vault>'
  }
  {
    name: 'connection-to-site2'
    vpnGatewayName: '${prefix}-${region}-vnet-gw-01'
    localNetworkGatewayName: '${prefix}-${region}-lng-site2-01'
    sharedKey: '<key-from-vault>'
  }
]
```

### Add VNet Peering

Enable the commented VNet peering section in parameters:

```bicep
param vnetPeerings = [
  {
    name: '${prefix}-${region}-vnet-c-01-to-vnet-c-vpn-01'
    remoteVirtualNetworkName: '${prefix}-${region}-vnet-c-vpn-01'
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: true
  }
]
```

---

## Security Best Practices

### 1. Service Principal Permissions

Grant minimum required permissions:
```bash
# Subscription-level Contributor (required for resource group creation)
az role assignment create \
  --assignee <service-principal-id> \
  --role Contributor \
  --scope /subscriptions/<subscription-id>
```

### 2. Approval Process

Configure multi-person approval:
1. Environment → **Approvals and checks**
2. **Approvers**: Select 2+ senior team members
3. Enable:
   - ☑️ **Require re-approval after changes**
   - ☑️ **Instructions to approvers**: Add deployment checklist

### 3. Branch Protection

Protect `main` branch:
1. **Repos** → **Branches** → `main` → **Branch policies**
2. Enable:
   - ☑️ Require a minimum of 2 reviewers
   - ☑️ Check for linked work items
   - ☑️ Check for comment resolution
   - ☑️ Build validation (this pipeline)

### 4. Secrets Management

- ⛔ Never commit VPN shared keys to Git
- ✅ Use Azure Key Vault for secrets
- ✅ Enable Key Vault soft-delete and purge protection
- ✅ Audit Key Vault access with diagnostic logs

### 5. Network Security

- ✅ Use Network Security Groups (NSGs) on subnets
- ✅ Enable Azure Firewall for outbound traffic filtering
- ✅ Implement Azure DDoS Protection Standard (if required)
- ✅ Enable VPN Gateway diagnostics to Log Analytics

---

## Monitoring and Operations

### View Deployment Logs

```bash
# List recent deployments
az deployment sub list \
  --query "[?starts_with(name, 'azure-landing-zone')].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}" \
  --output table

# Show deployment details
az deployment sub show \
  --name <deployment-name> \
  --query "{Name:name, State:properties.provisioningState, Resources:properties.outputResources[].id}"
```

### Monitor VPN Gateway

```bash
# Check VPN Gateway provisioning
az network vnet-gateway show \
  --name azl-we-vnet-gw-01 \
  --resource-group azl-we-rsg-lz-network-01 \
  --query "{Name:name, State:provisioningState, GatewayType:gatewayType, SKU:sku.name}"

# Show VPN connection status
az network vpn-connection show \
  --name <connection-name> \
  --resource-group azl-we-rsg-lz-network-01 \
  --query "{Name:name, ConnectionStatus:connectionStatus, IngressBytes:ingressBytesTransferred, EgressBytes:egressBytesTransferred}"

# Show VPN connection metrics (last 1 hour)
az monitor metrics list \
  --resource <vpn-connection-resource-id> \
  --metric "TunnelIngressBytes,TunnelEgressBytes,TunnelBandwidth" \
  --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ') \
  --interval PT1M
```

### Azure Portal Monitoring

1. Navigate to **VPN Gateway** in Azure Portal
2. Click **Connections** → View connection status
3. Check **Metrics** for:
   - Tunnel Ingress/Egress Bytes
   - Tunnel Bandwidth
   - Point-to-Site Connection Count
4. Review **Diagnostics logs** in Log Analytics

---

## Cost Optimization

### Estimated Monthly Costs (West Europe)

| Resource | SKU/Size | Estimated Cost |
|----------|----------|----------------|
| VPN Gateway | VpnGw1AZ | ~€125/month |
| Public IP Address | Standard | ~€4/month |
| Virtual Networks | N/A | Free |
| Private DNS Zones | 6 zones | ~€3/month |
| Log Analytics Workspace | Pay-as-you-go | ~€5-50/month (depends on ingestion) |
| Resource Groups | N/A | Free |
| **Total** | | **~€140-180/month** |

### Cost Reduction Tips

1. **Non-production environments**: Use VpnGw1 (non-AZ) to save ~30%
2. **Development/Test**: Delete VPN Gateway when not in use
3. **Log Analytics**: Configure data retention (default 30 days, reduce to 7 for non-prod)
4. **Automation**: Schedule VPN Gateway shutdown/startup with Azure Automation

---

## Support and Resources

- **Azure VPN Gateway**: [Docs](https://learn.microsoft.com/azure/vpn-gateway/)
- **Azure Landing Zones**: [Architecture](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- **Azure Verified Modules**: [aka.ms/avm](https://aka.ms/avm)
- **Bicep Documentation**: [Docs](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- **Get to the Cloud**: [https://www.gettothe.cloud](https://www.gettothe.cloud)

---

**Author**: Alex ter Neuzen  
**Website**: [GetToThe.Cloud](https://www.gettothe.cloud)  
**Last Updated**: February 2026
