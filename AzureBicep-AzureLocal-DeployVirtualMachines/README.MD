# Azure Local - Virtual Machine Deployment with Bicep

This Bicep template deploys a virtual machine on Azure Stack HCI (Azure Local) with automatic domain join capabilities.

## Overview

This solution deploys a complete virtual machine infrastructure on Azure Stack HCI, including:
- Arc Machine resource
- Virtual machine instance
- Network interface
- Additional data disk
- Automated domain join extension

## Prerequisites

- Azure Stack HCI cluster with Arc integration
- Custom location configured for the cluster
- Logical network configured
- Marketplace gallery image available
- Azure Key Vault with the following secrets:
  - `localAdminPassword` - Local administrator password
  - `localAdminAccount` - Local administrator account name
  - `domainJoinPassword` - Domain join account password
  - `domainJoinAccount` - Domain join account username
- Azure DevOps service connection configured (for pipeline deployment)

## Files

- **azlocal-bicep-new-virtualmachine.bicep** - Main Bicep template
- **azlocal-bicep-new-virtualmachine.parameters.bicepparam** - Parameter file with default values
- **azlocal-bicep-new-virtualmachine.yml** - Azure DevOps pipeline for automated deployment
- **modules/** - Modular Bicep components
  - `arcMachine.bicep` - Creates the Arc Machine resource
  - `vmInstance.bicep` - Deploys the VM instance
  - `networkInterface.bicep` - Configures network connectivity
  - `virtualHardDisk.bicep` - Creates additional data disks
  - `domainJoin.bicep` - Handles domain join extension

## Parameters

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `name` | string | Name of the virtual machine | `Test-VM` |
| `location` | string | Azure region | `westeurope` |
| `domainToJoin` | string | Active Directory domain to join | `azurelocalbox.local` |
| `orgUnitPath` | string | OU path for domain join | `OU=Servers,OU=Computers,DC=domain,DC=local` |
| `clusterRsg` | string | Resource group containing HCI cluster | `azl-we-rsg-azl-koogaandezaan-01` |
| `customLocationName` | string | Name of the custom location | `Koog-aan-de-Zaan` |
| `imageName` | string | Marketplace gallery image name | `2025-datacenter-azure-edition-02` |
| `subscriptionId` | string | Azure subscription ID | - |
| `logicalNetworkName` | string | Logical network name | `vnet101` |
| `keyVault` | string | Key Vault name | `azl-we-kv-cluster1-01` |
| `processorCores` | int | Number of CPU cores | `4` |
| `memoryInGB` | int | Memory in GB | `8` |
| `resourceTags` | object | Resource tags | `{ owner: 'Name', Purpose: 'Description' }` |

## Deployment

### Using Azure CLI

```bash
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file azlocal-bicep-new-virtualmachine.bicep \
  --parameters azlocal-bicep-new-virtualmachine.parameters.bicepparam
```

### Using Azure DevOps Pipeline

1. Import the pipeline: azlocal-bicep-new-virtualmachine.yml
2. Configure the variable group `azlocal-defaults` with:
   - `azureSubscription` - Service connection name
   - `subscriptionId` - Azure subscription ID
   - `resourceGroupName` - Target resource group
   - `location` - Azure region
3. Run the pipeline and provide parameters:
   - Virtual Machine Name
   - Image selection
   - Processor cores
   - Memory (GB)
   - Environment tag

The pipeline performs validation before deployment.

## Outputs

| Output | Description |
|--------|-------------|
| `vmName` | Name of the deployed virtual machine |
| `arcMachineId` | Resource ID of the Arc Machine |
| `networkInterfaceId` | Resource ID of the network interface |

## Post-Deployment

### Arc Gateway Association (Optional)

After deployment, associate the VM with an Arc Gateway using Azure CLI:

```bash
az arcgateway settings update \
  --resource-group <arc-gateway-rsg> \
  --subscription <subscription-id> \
  --base-provider Microsoft.HybridCompute \
  --base-resource-type machines \
  --base-resource-name <vm-name> \
  --gateway-resource-id "/subscriptions/<subscription-id>/resourceGroups/<arc-gateway-rsg>/providers/Microsoft.HybridCompute/gateways/<gateway-name>"
```

## Architecture

```
┌─────────────────────────────────────────┐
│         Azure Stack HCI Cluster         │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │       Custom Location             │  │
│  │                                   │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │     Arc Machine             │  │  │
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │  VM Instance          │  │  │  │
│  │  │  │  - OS Disk (Image)    │  │  │  │
│  │  │  │  - Data Disk          │  │  │  │
│  │  │  │  - Network Interface  │  │  │  │
│  │  │  │  - Domain Join Ext    │  │  │  │
│  │  │  └───────────────────────┘  │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
           │
           │ Secrets
           ▼
    ┌──────────────┐
    │  Key Vault   │
    └──────────────┘
```

## Notes

- Default local admin account: `vmadmin`
- Default domain join account: `domain_join`
- Data disk size: 10 GB (dynamic)
- VM provisioning agents are automatically enabled
- Domain join occurs automatically after VM provisioning

## Author

Alex ter Neuzen

## License

See LICENSE file in the repository root.
