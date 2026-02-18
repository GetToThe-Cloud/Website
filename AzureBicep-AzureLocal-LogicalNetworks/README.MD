# Azure Stack HCI Logical Networks - Bicep Deployment

This repository contains Bicep templates for deploying logical networks on Azure Stack HCI (Azure Local) clusters using Azure Verified Modules (AVM).

## Overview

The templates in this repository enable automated deployment of logical networks for Azure Stack HCI, providing network segmentation, IP address management, and VLAN configuration. The solution leverages the official Azure Verified Module pattern to ensure best practices and maintainability.

## Files

- **azlocal-logical-network.bicep** - Main Bicep template that deploys logical networks using a modular, array-based approach
- **azlocal-logical-network.parameters.bicepparam** - Parameter file containing network configurations
- **DevOps Pipeline/azure-pipelines.yml** - Azure DevOps CI/CD pipeline for automated deployment
- **DevOps Pipeline/PIPELINE-SETUP.md** - Complete guide for setting up the deployment pipeline

## Features

- ✅ Deploys multiple logical networks from a single template
- ✅ Supports VLAN segmentation
- ✅ Configurable IP address pools with static or dynamic allocation
- ✅ DNS server configuration
- ✅ Default gateway routing
- ✅ Custom resource tagging
- ✅ Uses Azure Verified Modules (AVM) for Azure Stack HCI logical networks

## Prerequisites

- Azure Stack HCI cluster (Azure Local) deployed and registered with Azure
- Custom location configured for your Azure Stack HCI cluster
- Virtual switch created on the Azure Stack HCI cluster
- Azure subscription with appropriate permissions
- Bicep CLI installed (Azure CLI includes Bicep)

## Parameters

### Main Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `subscriptionId` | string | Yes | Azure subscription ID where resources will be deployed |
| `paramsNetworks` | array | Yes | Array of network configuration objects |

### Network Configuration Object

Each network object in the `paramsNetworks` array contains:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `parName` | string | Yes | Name of the logical network |
| `parResourceGroupName` | string | Yes | Resource group containing the custom location |
| `parLocation` | string | Yes | Azure region (e.g., 'westeurope') |
| `parSubscriptionId` | string | Yes | Azure subscription ID |
| `parExtendedLocationName` | string | Yes | Name of the custom location (Azure Stack HCI cluster) |
| `parVSwitchName` | string | Yes | Name of the virtual switch on the cluster |
| `parAddressPrefix` | string | Yes | IP address prefix in CIDR notation (e.g., '172.16.1.0/24') |
| `parVlan` | integer | Yes | VLAN ID for network segmentation (use 0 for untagged) |
| `parIpAllocationMethod` | string | Yes | IP allocation method ('Static' or 'Dynamic') |
| `parDnsServers` | array | Yes | Array of DNS server IP addresses |
| `parDefaultGateway` | string | Yes | Default gateway IP address |
| `parIpPools` | array | Yes | Array of IP pool objects with 'start' and 'end' properties |
| `parTags` | object | No | Resource tags as key-value pairs |

## Usage

### 1. Configure Parameters

Edit the [azlocal-logical-network.parameters.bicepparam](azlocal-logical-network.parameters.bicepparam) file with your environment-specific values:

```bicep
param subscriptionId = '00000000-0000-0000-0000-000000000000'

param paramsNetworks = [
  {
    parName: 'azlocal-eastus2-01-logical-network-compute'
    parResourceGroupName: 'azlocal-eastus2-01-rg'
    parLocation: 'westeurope'
    parSubscriptionId: subscriptionId
    parExtendedLocationName: 'azlocal-eastus2-01'
    parVSwitchName: 'ConvergedSwitch(compute_management_storage)'
    parAddressPrefix: '172.16.1.0/24'
    parVlan: 100
    parIpAllocationMethod: 'Static'
    parDnsServers: [
      '172.16.1.10'
    ]
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

### 2. Deploy Using Azure DevOps Pipeline (Recommended)

For automated, repeatable deployments with approval gates and validation:

1. **Import the pipeline** from [DevOps Pipeline/azure-pipelines.yml](DevOps%20Pipeline/azure-pipelines.yml)
2. **Configure the environment** and service connection
3. **Update parameters** in the bicepparam file
4. **Push to main branch** to trigger automatic deployment

**Pipeline Features**:
- ✅ Automated validation with What-If analysis
- ✅ Bicep build and syntax checking
- ✅ Custom location verification
- ✅ Manual approval gate before deployment
- ✅ Automated verification and reporting

See [DevOps Pipeline/PIPELINE-SETUP.md](DevOps%20Pipeline/PIPELINE-SETUP.md) for complete setup instructions.

### 3. Deploy Using Azure CLI

```bash
# Login to Azure
az login

# Set the subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Deploy the template
az deployment sub create \
  --name logical-network-deployment \
  --location westeurope \
  --template-file azlocal-logical-network.bicep \
  --parameters azlocal-logical-network.parameters.bicepparam
```

### 4. Deploy Using PowerShell

```powershell
# Login to Azure
Connect-AzAccount

# Set the subscription
Set-AzContext -SubscriptionId "YOUR_SUBSCRIPTION_ID"

# Deploy the template
New-AzDeployment `
  -Name "logical-network-deployment" `
  -Location "westeurope" `
  -TemplateFile "azlocal-logical-network.bicep" `
  -TemplateParameterFile "azlocal-logical-network.parameters.bicepparam"
```

## Multiple Network Deployment

You can deploy multiple logical networks by adding additional network objects to the `paramsNetworks` array:

```bicep
param paramsNetworks = [
  {
    parName: 'logical-network-compute'
    // ... compute network configuration
  },
  {
    parName: 'logical-network-management'
    // ... management network configuration
  },
  {
    parName: 'logical-network-storage'
    // ... storage network configuration
  }
]
```

## Network Planning Considerations

- **IP Address Pools**: Ensure IP ranges don't overlap with existing infrastructure
- **VLAN IDs**: Coordinate VLAN assignments with your network team
- **DNS Servers**: Use reliable, accessible DNS servers for your environment
- **Gateway Configuration**: Verify gateway IP matches your network infrastructure
- **Address Prefix**: Use appropriate CIDR notation for your subnet size

## Validation

After deployment, verify the logical networks:

```bash
# List logical networks
az stack-hci-vm network lnet list \
  --resource-group YOUR_RESOURCE_GROUP

# Show specific logical network details
az stack-hci-vm network lnet show \
  --name YOUR_NETWORK_NAME \
  --resource-group YOUR_RESOURCE_GROUP
```

## Troubleshooting

Common issues and solutions:

1. **Custom Location Not Found**: Ensure the custom location name matches exactly and is in the correct resource group
2. **Virtual Switch Name**: Verify the vSwitch name matches what's configured on your Azure Stack HCI cluster
3. **IP Address Conflicts**: Check that IP pools don't conflict with existing network allocations
4. **VLAN Configuration**: Ensure VLAN IDs are properly configured on physical network infrastructure

## References

- [Azure Stack HCI Documentation](https://learn.microsoft.com/azure-stack/hci/)
- [Azure Verified Modules - Logical Network](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/azure-stack-hci/logical-network)
- [Azure Stack HCI Networking](https://learn.microsoft.com/azure-stack/hci/manage/create-logical-networks)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## License

This project is provided as-is for educational and deployment purposes.

## Contributing

Contributions are welcome! Please ensure any modifications follow Azure Verified Module patterns and best practices.

## Version History

- **0.2.1** - Using Azure Verified Module version 0.2.1 for logical networks
- Initial release - Basic logical network deployment template
