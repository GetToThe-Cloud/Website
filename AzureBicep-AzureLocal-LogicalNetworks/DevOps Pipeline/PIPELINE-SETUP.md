# Azure DevOps Pipeline Setup Guide
## Azure Stack HCI Logical Networks Deployment

This guide walks you through setting up the Azure DevOps pipeline for automated deployment of logical networks to Azure Stack HCI (Azure Local).

---

## Prerequisites

### 1. Azure Service Connection

1. Go to **Project Settings** → **Service connections**
2. Click **New service connection** → **Azure Resource Manager**
3. Select **Service principal (automatic)**
4. Configure the connection:
   - **Subscription**: Select your Azure subscription
   - **Resource group**: Leave empty (subscription-level access)
   - **Service connection name**: `Azure-ServiceConnection`
   - **Grant access permission to all pipelines**: ☑️ Enabled
5. Click **Save**

> **Note**: The service principal needs `Contributor` role at subscription level to deploy Azure Stack HCI resources.

### 2. Azure DevOps Environment

Create an environment for deployment approvals:

1. Go to **Pipelines** → **Environments**
2. Click **New environment**
3. Configure:
   - **Name**: `production-azlocal`
   - **Description**: "Production Azure Stack HCI environment"
   - **Resource**: None
4. Click **Create**
5. Add **Approvals**:
   - Click on the environment → **⋯** → **Approvals and checks**
   - Add **Approvals** → Select approvers
   - Configure approval policy (recommended: require 1-2 approvers)

### 3. Azure Stack HCI Prerequisites

Ensure you have:
- ✅ Azure Stack HCI cluster deployed and registered with Azure
- ✅ Custom location configured (`az customlocation list`)
- ✅ Virtual switch created on the cluster
- ✅ Network IP ranges and VLAN configuration documented
- ✅ DNS server addresses available

---

## Pipeline Setup

### 1. Import Pipeline

1. **Pipelines** → **New pipeline**
2. Select **Azure Repos Git** (or your repository location)
3. Select your repository
4. Choose **Existing Azure Pipelines YAML file**
5. Select: `/AzureBicep-AzureLocal-LogicalNetworks/DevOps Pipeline/azure-pipelines.yml`
6. Click **Continue** → **Save**

### 2. Pipeline Stages

The pipeline consists of three stages:

### Stage 1: Validate (5 minutes)

- ✅ Bicep build and syntax check
- ✅ Parameters file validation
- ✅ Azure deployment validation
- ✅ What-If analysis preview
- ✅ Custom location availability check
- ✅ Artifact publishing

### Stage 2: Deploy (10-15 minutes)

- 🚀 Deploy logical networks to Azure Stack HCI
- 🔐 Requires manual approval from `production-azlocal` environment
- 📊 Retrieves deployment outputs and resource IDs

### Stage 3: Verify (2 minutes)

- ✔️ Verify logical networks exist
- ✔️ Check network configuration details
- 📄 Generate deployment report

---

## Configuration

### Update Pipeline Variables

Edit the pipeline YAML file and update these variables:

```yaml
variables:
  - name: serviceConnection
    value: 'Azure-ServiceConnection' # Your service connection name
```

### Configure Parameters

Edit [azlocal-logical-network.parameters.bicepparam](../azlocal-logical-network.parameters.bicepparam):

```bicep
param subscriptionId = '00000000-0000-0000-0000-000000000000'

param paramsNetworks = [
  {
    parName: 'azlocal-we-lnet-compute'
    parResourceGroupName: 'azlocal-we-rg'
    parLocation: 'westeurope'
    parSubscriptionId: subscriptionId
    parExtendedLocationName: 'azlocal-we-customlocation'
    parVSwitchName: 'ConvergedSwitch(compute_management_storage)'
    parAddressPrefix: '172.16.1.0/24'
    parVlan: 100
    parIpAllocationMethod: 'Static'
    parDnsServers: ['172.16.1.10', '172.16.1.11']
    parDefaultGateway: '172.16.1.1'
    parIpPools: [
      {
        start: '172.16.1.200'
        end: '172.16.1.215'
      }
    ]
    parTags: {
      environment: 'production'
      project: 'azure-stack-hci'
    }
  }
]
```

---

## Running the Pipeline

### Automatic Trigger

The pipeline automatically triggers when:
- Code is pushed to `main` branch
- Files in `AzureBicep-AzureLocal-LogicalNetworks/` are modified

### Manual Trigger

1. Go to **Pipelines** → Select your pipeline
2. Click **Run pipeline**
3. Select branch (default: `main`)
4. Click **Run**

### Monitoring Deployment

1. **Validate Stage**: Runs automatically (no approval needed)
   - Check What-If analysis output
   - Review planned changes
   
2. **Deploy Stage**: Requires manual approval
   - Review validation results
   - Click **Approve** to proceed
   - Monitor deployment progress

3. **Verify Stage**: Runs automatically after deployment
   - Review logical network status
   - Check deployment report

---

## Troubleshooting

### Issue: "Custom location not found"

**Solution**:
```bash
# Verify custom location exists
az customlocation list --resource-group <your-rg> --output table

# Check custom location status
az customlocation show --name <custom-location-name> --resource-group <your-rg>
```

### Issue: "Deployment validation failed"

**Causes**:
- Resource group does not exist
- Custom location not registered
- Insufficient permissions
- Invalid IP ranges or VLAN configuration

**Solution**:
```bash
# Check resource group exists
az group show --name <your-rg>

# Verify service principal has access
az role assignment list --scope /subscriptions/<subscription-id>/resourceGroups/<your-rg>

# Validate parameters manually
az deployment group validate \
  --resource-group <your-rg> \
  --template-file azlocal-logical-network.bicep \
  --parameters azlocal-logical-network.parameters.bicepparam
```

### Issue: "Logical networks deployment timeout"

**Solution**:
- Increase pipeline timeout in YAML
- Check Azure Stack HCI cluster health
- Verify Arc connection is active

### Issue: "IP pool conflicts"

**Causes**:
1. IP range already in use
2. Overlapping IP pools
3. Invalid CIDR notation

**Solution**:
- Document and track all IP assignments
- Use IP Address Management (IPAM) tool
- Validate IP ranges before deployment

---

## Advanced Configuration

### Multiple Networks Deployment

Configure multiple logical networks in one deployment:

```bicep
param paramsNetworks = [
  {
    parName: 'azlocal-we-lnet-compute'
    parAddressPrefix: '172.16.1.0/24'
    parVlan: 100
    // ... other settings
  },
  {
    parName: 'azlocal-we-lnet-storage'
    parAddressPrefix: '172.16.2.0/24'
    parVlan: 200
    // ... other settings
  },
  {
    parName: 'azlocal-we-lnet-management'
    parAddressPrefix: '172.16.3.0/24'
    parVlan: 300
    // ... other settings
  }
]
```

### Environment-Specific Parameters

Create separate parameter files:

```yaml
# Development
azlocal-logical-network.parameters.dev.bicepparam

# Production
azlocal-logical-network.parameters.prod.bicepparam
```

Update pipeline to use environment-specific files:

```yaml
variables:
  - name: bicepParameters
    value: 'azlocal-logical-network.parameters.$(Environment).bicepparam'
```

### Notifications

Add email notifications on pipeline completion:

1. **Project Settings** → **Notifications**
2. **New subscription** → **Build**
3. Configure:
   - **Event**: Build completes
   - **Filter**: Your pipeline
   - **Recipients**: Team members

---

## Security Best Practices

### 1. Parameter Protection

Store sensitive values in Azure Key Vault:

```bicep
param dnsServers array = [
  az.keyVault().getSecret('DNS-Server-1')
  az.keyVault().getSecret('DNS-Server-2')
]
```

### 2. Service Connection Permissions

Grant minimum required permissions:
- `Contributor` on specific resource groups (preferred)
- Avoid subscription-level `Owner` role

### 3. Approval Process

Configure approval policies:
1. Go to environment `production-azlocal`
2. Add **Approvals** → Configure:
   - **Approvers**: 2+ team members
   - **Timeout**: 48 hours
   - **Require comment**: ☑️ Enabled

### 4. Branch Protection

Protect `main` branch:
1. **Repos** → **Branches**
2. Select `main` → **Branch policies**
3. Enable:
   - ☑️ Require a minimum number of reviewers (2)
   - ☑️ Check for linked work items
   - ☑️ Build validation (pipeline must succeed)

---

## Pipeline Artifacts

The pipeline publishes artifacts for troubleshooting:

### Published Artifacts:
- **bicep-templates**: Compiled templates and parameters
- **deployment-outputs**: Resource IDs and configuration

### Download Artifacts:

1. Go to pipeline run
2. Click **📦 Artifacts** tab
3. Download `bicep-templates` artifact
4. Extract and review files

---

## Monitoring and Logging

### View Deployment Logs

```bash
# Get recent deployments
az deployment group list \
  --resource-group <your-rg> \
  --query "[].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}" \
  --output table

# Get deployment details
az deployment group show \
  --resource-group <your-rg> \
  --name <deployment-name> \
  --output json
```

### Check Logical Network Status

```bash
# List all logical networks
az stack-hci-vm network lnet list \
  --resource-group <your-rg> \
  --output table

# Get specific network details
az stack-hci-vm network lnet show \
  --name <network-name> \
  --resource-group <your-rg>
```

### Azure Portal Monitoring

1. Navigate to your resource group in Azure Portal
2. Filter resource type: **Logical networks**
3. Click on a network → **Overview**
4. Review:
   - Provisioning state
   - IP configuration
   - VLAN settings
   - Connected VMs

---

## Support and Resources

- **Azure Stack HCI Docs**: [aka.ms/AzureStackHCI](https://aka.ms/AzureStackHCI)
- **Azure Local (HCI) Arc VMs**: [Azure Arc VM Management](https://learn.microsoft.com/azure/azure-arc/servers/overview)
- **Logical Networks**: [Create Logical Networks](https://learn.microsoft.com/azure-stack/hci/manage/create-logical-networks)
- **Azure Verified Modules**: [aka.ms/avm](https://aka.ms/avm)
- **Get to the Cloud**: [https://www.gettothe.cloud](https://www.gettothe.cloud)

---

**Author**: Alex ter Neuzen  
**Website**: [GetToThe.Cloud](https://www.gettothe.cloud)  
**Last Updated**: February 2026
