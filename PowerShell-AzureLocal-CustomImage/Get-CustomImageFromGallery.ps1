
# ------------------------------------------
# Script: Import Latest Azure Compute Gallery Image into Azure Stack HCI
# ------------------------------------------
# Summary:
#   - Creates an Azure Stack HCI storage path resource
#   - Finds the latest (non-excluded) version of a gallery image
#   - Exports it to a temporary managed disk with SAS access
#   - Imports the image into Azure Stack HCI via az stack-hci-vm
#   - Cleans up temporary disk and access
#
# Requirements:
#   - Azure CLI (az) installed and logged in
#   - Az PowerShell modules installed (for Get-AzGalleryImageVersion)
#   - Permissions to read gallery, create disks, manage Azure Stack HCI resources
#   - Azure Stack HCI ARC-connected with a valid Custom Location
#
# Notes:
#   - Make sure to define $imgResourceGroup (used but not defined in original snippet)
#   - Image OS type set to "Windows" (adjust if importing Linux)
#   - Region/location references must be consistent with your resources
# 
# Author: 
#   - Alex ter Neuzen for GetToTheCloud 2026
# ------------------------------------------

# 1) Authenticate to Azure
az login

# 2) Allow installing CLI extensions automatically without prompts
az config set extension.use_dynamic_install=yes_without_prompt

# 3) USER-DEFINED VARIABLES (adjust these to your environment)
$storagepathname   = "Images"                              # Name of the HCI storage path resource
$path              = "C:\ClusterStorage\UserStorage_1\Images"  # CSV path on your HCI cluster
$resource_group    = "<cluster resource group>"            # RG that contains Custom Location & HCI resources
$customLocationName= "<your custom location>"              # Name of the custom location bound to HCI
$location          = "WestEurope"                          # Azure region for metadata/management resources
$gallery           = "<your image gallery>"                # Azure Compute Gallery name
$definition        = "<your image definition>"             # Image definition name in the gallery
$imgResourceGroup  = "<image resource group>"              # RG containing the gallery and for temp disk

# 4) Resolve the Custom Location resource ID (used by HCI VM commands)
$customLocationID = az customlocation show `
  --resource-group $resource_group `
  --name $customLocationName `
  --query id -o tsv

# 5) Create the Azure Stack HCI storage path resource (logical pointer to CSV path)
#    This registers the on-host path so images can be stored there by HCI VM service.
az stack-hci-vm storagepath create `
  --resource-group $resource_group `
  --custom-location $customLocationID `
  --name $storagepathname `
  --path $path

# 6) Get the latest (non-excluded) image version from the Azure Compute Gallery
#    Requires Az PowerShell modules (Az.Compute). It filters versions where
#    PublishingProfile.ExcludeFromLatest is $false and picks the newest.
$sourceImgVer = Get-AzGalleryImageVersion `
  -GalleryImageDefinitionName $definition `
  -GalleryName $gallery `
  -ResourceGroupName $imgResourceGroup |
  Where-Object { $_.PublishingProfile.ExcludeFromLatest -eq $false } |
  Select-Object -Last 1

# 7) Create a temporary managed disk from the gallery image version for export
#    The disk name replaces dots in the version name with dashes to comply with naming rules.
az disk create `
  --resource-group $imgResourceGroup `
  --location $location `
  --name $($sourceImgVer.name.Replace(".","-")) `
  --gallery-image-reference $sourceImgVer.id

# 8) Grant read-only SAS access to the managed disk so HCI can download the image
#    Duration is set to 8 hours (28800 seconds)—adjust if your network requires more time.
$imageSourcePath = (
  az disk grant-access `
    --access-level read `
    --resource-group $imgResourceGroup `
    --name $($sourceImgVer.name.Replace(".","-")) `
    --duration-in-seconds 28800 |
  ConvertFrom-Json
).accessSAS

# 9) Prepare metadata for HCI image creation
$osType = "Windows"                                 # Change to "Linux" if needed
$imageName = $sourceImgVer.name.Replace(".","-")    # Name for the image in HCI
$StoragePathID = az stack-hci-vm storagepath show `
  --resource-group $resource_group `
  --name $storagepathname `
  --query id -o tsv

# 10) Create the image in Azure Stack HCI (downloads from SAS and registers it)
#     --image-path is the SAS URL returned in step 8
az stack-hci-vm image create `
  --resource-group $resource_group `
  --custom-location $customLocationID `
  --location $location `
  --name $imageName `
  --os-type $osType `
  --image-path $imageSourcePath `
  --storage-path-id $StoragePathID

# 11) Revoke SAS access to the temporary managed disk (security best practice)
az disk revoke-access `
  --name $($sourceImgVer.name.Replace(".","-")) `
  --resource-group $imgResourceGroup

# 12) Delete the temporary managed disk to avoid ongoing costs
az disk delete `
  --name $($sourceImgVer.name.Replace(".","-")) `
  --resource-group $imgResourceGroup `
  --yes
``
