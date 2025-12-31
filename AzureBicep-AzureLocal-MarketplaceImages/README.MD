# Azure Stack HCI Marketplace Gallery Images - Bicep Deployment

This repository contains Bicep templates for deploying Azure Marketplace gallery images to Azure Stack HCI (Azure Local) clusters using Azure Verified Modules (AVM).

## Overview

The templates enable automated deployment of multiple marketplace images from Azure to your Azure Stack HCI cluster. This simplifies the process of making Azure Marketplace images (Windows Server, Windows 11, Linux distributions) available for VM deployment on your local infrastructure.

## Files

- **azlocal-bicep-image.bicep** - Main Bicep template that deploys marketplace gallery images using a modular, array-based approach
- **azlocal-bicep-image.parameters.bicepparam** - Parameter file containing image configurations with preconfigured examples

## Features

- ✅ Deploy multiple marketplace images from a single template
- ✅ Support for Windows and Linux operating systems
- ✅ Hyper-V Generation V1 and V2 support
- ✅ Specific version pinning for consistent deployments
- ✅ Custom resource tagging
- ✅ Uses Azure Verified Modules (AVM) for Azure Stack HCI marketplace images
- ✅ Pre-configured examples for common images (Windows Server 2022/2025, Windows 11 AVD)

## Prerequisites

- Azure Stack HCI cluster (Azure Local) deployed and registered with Azure
- Custom location configured for your Azure Stack HCI cluster
- Internet connectivity to access Azure Marketplace
- Azure subscription with appropriate permissions
- Bicep CLI installed (Azure CLI includes Bicep)

## Parameters

### Main Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `subscriptionId` | string | Yes | Azure subscription ID where resources will be deployed |
| `location` | string | Yes | Azure region for resource metadata (e.g., 'westeurope') |
| `paramsImage` | array | Yes | Array of image configuration objects |

### Image Configuration Object

Each image object in the `paramsImage` array contains:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `parImageName` | string | Yes | Display name for the marketplace image |
| `parResourceGroupName` | string | Yes | Resource group containing the custom location |
| `parSubscriptionId` | string | Yes | Azure subscription ID |
| `parExtendedLocationName` | string | Yes | Name of the custom location (Azure Stack HCI cluster) |
| `parOsType` | string | Yes | Operating system type ('Windows' or 'Linux') |
| `parPublisherId` | string | Yes | Publisher ID from Azure Marketplace |
| `parOfferId` | string | Yes | Offer ID from Azure Marketplace |
| `parSku` | string | Yes | SKU from Azure Marketplace |
| `parSkuVersion` | string | Yes | Specific version of the SKU |
| `parHyperVGeneration` | string | Yes | Hyper-V generation ('V1' or 'V2') |
| `parTags` | object | No | Resource tags as key-value pairs |

## Pre-configured Images

The template includes examples for these popular images:

### Windows Desktop Images
- **Windows 11 24H2 AVD with Microsoft 365** (`win11-24h2-avd-m365`)
- **Windows 11 25H2 AVD with Microsoft 365** (`win11-25h2-avd-m365`)

### Windows Server Images
- **Windows Server 2025 Datacenter Azure Edition** (`2025-datacenter-azure-edition`)
- **Windows Server 2022 Datacenter Azure Edition** (`2022-datacenter-azure-edition`)

## Usage

### 1. Configure Parameters

Edit the [azlocal-bicep-image.parameters.bicepparam](azlocal-bicep-image.parameters.bicepparam) file with your environment-specific values:

```bicep
param subscriptionId = '00000000-0000-0000-0000-000000000000'
param location = 'westeurope'

param paramsImage = [
  {
    parImageName: 'win11-24h2-avd-m365-01'
    parResourceGroupName: 'azlocal-rg'
    parSubscriptionId: subscriptionId
    parExtendedLocationName: 'azlocal-cluster-01'
    parOsType: 'Windows'
    parPublisherId: 'microsoftwindowsdesktop'
    parOfferId: 'office-365'
    parSku: 'win11-24h2-avd-m365'
    parSkuVersion: '26100.7462.251209'
    parHyperVGeneration: 'V2'
    parTags: {
      environment: 'production'
      imageType: 'avd'
    }
  }
]
```

### 2. Deploy Using Azure CLI

```bash
# Login to Azure
az login

# Set the subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Deploy the template
az deployment group create \
  --name marketplace-image-deployment \
  --resource-group YOUR_RESOURCE_GROUP \
  --template-file azlocal-bicep-image.bicep \
  --parameters azlocal-bicep-image.parameters.bicepparam
```

### 3. Deploy Using PowerShell

```powershell
# Login to Azure
Connect-AzAccount

# Set the subscription
Set-AzContext -SubscriptionId "YOUR_SUBSCRIPTION_ID"

# Deploy the template
New-AzResourceGroupDeployment `
  -Name "marketplace-image-deployment" `
  -ResourceGroupName "YOUR_RESOURCE_GROUP" `
  -TemplateFile "azlocal-bicep-image.bicep" `
  -TemplateParameterFile "azlocal-bicep-image.parameters.bicepparam"
```

## Finding Marketplace Image Details

To find the correct publisher, offer, SKU, and version information for other marketplace images:

### Using Azure CLI

```bash
# List publishers
az vm image list-publishers --location westeurope --output table

# List offers for a publisher
az vm image list-offers \
  --publisher microsoftwindowsserver \
  --location westeurope \
  --output table

# List SKUs for an offer
az vm image list-skus \
  --publisher microsoftwindowsserver \
  --offer windowsserver \
  --location westeurope \
  --output table

# List all versions for a SKU
az vm image list \
  --publisher microsoftwindowsserver \
  --offer windowsserver \
  --sku 2025-datacenter-azure-edition \
  --location westeurope \
  --all \
  --output table
```

### Using PowerShell

```powershell
# List publishers
Get-AzVMImagePublisher -Location "westeurope" | Select-Object PublisherName

# List offers for a publisher
Get-AzVMImageOffer `
  -Location "westeurope" `
  -PublisherName "microsoftwindowsserver"

# List SKUs for an offer
Get-AzVMImageSku `
  -Location "westeurope" `
  -PublisherName "microsoftwindowsserver" `
  -Offer "windowsserver"

# List all versions for a SKU
Get-AzVMImage `
  -Location "westeurope" `
  -PublisherName "microsoftwindowsserver" `
  -Offer "windowsserver" `
  -Sku "2025-datacenter-azure-edition"
```

## Common Publisher/Offer/SKU Combinations

### Windows Server
| Publisher | Offer | SKU | Description |
|-----------|-------|-----|-------------|
| `microsoftwindowsserver` | `windowsserver` | `2025-datacenter-azure-edition` | Windows Server 2025 Datacenter Azure Edition |
| `microsoftwindowsserver` | `windowsserver` | `2022-datacenter-azure-edition` | Windows Server 2022 Datacenter Azure Edition |
| `microsoftwindowsserver` | `windowsserver` | `2019-datacenter` | Windows Server 2019 Datacenter |

### Windows Desktop (AVD)
| Publisher | Offer | SKU | Description |
|-----------|-------|-----|-------------|
| `microsoftwindowsdesktop` | `office-365` | `win11-25h2-avd-m365` | Windows 11 25H2 AVD with M365 Apps |
| `microsoftwindowsdesktop` | `office-365` | `win11-24h2-avd-m365` | Windows 11 24H2 AVD with M365 Apps |
| `microsoftwindowsdesktop` | `windows-11` | `win11-25h2-avd` | Windows 11 25H2 AVD (no M365) |
| `microsoftwindowsdesktop` | `windows-10` | `win10-22h2-avd` | Windows 10 22H2 AVD |

### Linux
| Publisher | Offer | SKU | Description |
|-----------|-------|-----|-------------|
| `canonical` | `0001-com-ubuntu-server-jammy` | `22_04-lts-gen2` | Ubuntu Server 22.04 LTS |
| `redhat` | `rhel` | `9-lvm-gen2` | Red Hat Enterprise Linux 9 |

## Multiple Image Deployment

Deploy multiple images simultaneously by adding objects to the `paramsImage` array:

```bicep
param paramsImage = [
  {
    // Windows Server 2025
    parImageName: '2025-datacenter-azure-edition-01'
    // ... configuration
  },
  {
    // Windows 11 AVD
    parImageName: 'win11-24h2-avd-m365-01'
    // ... configuration
  },
  {
    // Ubuntu Server
    parImageName: 'ubuntu-server-2204-01'
    // ... configuration
  }
]
```

## Image Selection Considerations

- **Hyper-V Generation**: Generation 2 VMs offer better performance and security (UEFI, Secure Boot)
- **Version Pinning**: Specify exact versions for consistency across deployments
- **AVD Images**: Include M365 Apps if needed for Azure Virtual Desktop workloads
- **Azure Edition**: Windows Server Azure Edition includes Azure-specific optimizations
- **Licensing**: Ensure proper licensing for Windows images in on-premises scenarios

## Validation

After deployment, verify the marketplace images:

```bash
# List marketplace gallery images
az stack-hci-vm image list \
  --resource-group YOUR_RESOURCE_GROUP

# Show specific image details
az stack-hci-vm image show \
  --name YOUR_IMAGE_NAME \
  --resource-group YOUR_RESOURCE_GROUP
```

## Troubleshooting

Common issues and solutions:

1. **Custom Location Not Found**: Verify the custom location name and resource group are correct
2. **Image Download Fails**: Ensure Azure Stack HCI cluster has internet connectivity to Azure Marketplace
3. **Version Not Available**: Check that the specified version exists using the image listing commands
4. **Insufficient Storage**: Ensure adequate storage space on your Azure Stack HCI cluster
5. **Publisher/Offer/SKU Mismatch**: Verify all three values match a valid marketplace image combination

## Image Update Strategy

To update to newer image versions:

1. Find the latest version using Azure CLI/PowerShell commands
2. Update the `parSkuVersion` parameter in your configuration
3. Redeploy the template (existing deployments are not affected)
4. Update VM deployments to use the new image version

## Automation and CI/CD

This template is ideal for automation pipelines:

```yaml
# Example GitHub Actions workflow
- name: Deploy Marketplace Images
  run: |
    az deployment group create \
      --resource-group ${{ secrets.RESOURCE_GROUP }} \
      --template-file azlocal-bicep-image.bicep \
      --parameters azlocal-bicep-image.parameters.bicepparam
```

## References

- [Azure Stack HCI Documentation](https://learn.microsoft.com/azure-stack/hci/)
- [Azure Verified Modules - Marketplace Gallery Image](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/azure-stack-hci/marketplace-gallery-image)
- [Azure Stack HCI VM Image Management](https://learn.microsoft.com/azure-stack/hci/manage/virtual-machine-image-azure-marketplace)
- [Azure Marketplace Images](https://learn.microsoft.com/azure/virtual-machines/marketplace-images)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## License

This project is provided as-is for educational and deployment purposes.

## Contributing

Contributions are welcome! Please ensure any modifications follow Azure Verified Module patterns and best practices.

## Version History

- **0.1.0** - Using Azure Verified Module version 0.1.0 for marketplace gallery images
- Initial release - Support for Windows Server, Windows Desktop, and Linux marketplace images
