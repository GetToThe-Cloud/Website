
<#
.SYNOPSIS
    Imports custom VM images from Azure Compute Gallery to Azure Stack HCI.

.DESCRIPTION
    This script automates the process of importing VM images from an Azure Compute Gallery
    to an Azure Stack HCI cluster. The workflow includes:
    - Authenticating to Azure and setting the subscription context
    - Creating or validating storage path resources on the HCI cluster
    - Retrieving the latest non-excluded image version from Azure Compute Gallery
    - Creating a temporary managed disk from the gallery image
    - Generating SAS access to the disk for secure transfer
    - Importing the image into the HCI cluster's storage location
    
    This enables you to maintain consistent VM images across Azure and on-premises
    HCI environments, supporting hybrid cloud scenarios and golden image management.

.PARAMETER subscriptionId
    The Azure subscription ID where the resources are located.

.PARAMETER storagepathname
    The name of the HCI storage path resource that will be created or used.

.PARAMETER path
    The Cluster Shared Volume (CSV) path on the HCI cluster where images will be stored.

.PARAMETER resource_group
    The resource group containing the Custom Location and Azure Stack HCI resources.

.PARAMETER customLocationName
    The name of the custom location that is bound to the HCI cluster.

.PARAMETER location
    The Azure region for metadata and management resources.

.PARAMETER gallery
    The name of the Azure Compute Gallery containing the source images.

.PARAMETER definition
    The image definition name within the Azure Compute Gallery.

.PARAMETER imgResourceGroup
    The resource group containing the Azure Compute Gallery and temporary disk resources.

.NOTES
    File Name      : Get-PSCustomImageFromGallery.ps1
    Author         : GetToTheCloud
    Prerequisite   : Azure PowerShell modules (Az.Compute, Az.Resources, Az.StackHCI, Az.StackHCIVM)
    Version        : 1.0
    
.EXAMPLE
    .\Get-PSCustomImageFromGallery.ps1
    Runs the script with the configured parameters to import the latest image from Azure Compute Gallery to HCI.

.LINK
    https://learn.microsoft.com/azure/azure-local/
.LINK
    https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery
#>

#Requires -Modules Az.Accounts, Az.Compute, Az.Resources, Az.StackHCI, Az.StackHCIVM

# ============================================================
# Azure Authentication
# ============================================================

# Authenticate to Azure - this will prompt for credentials if not already authenticated
Write-Host "Authenticating to Azure..." -ForegroundColor Cyan
Connect-AzAccount

# ============================================================
# Module Import
# ============================================================

# Import required Azure PowerShell modules for compute, resource management, and HCI operations
Write-Host "Importing required PowerShell modules..." -ForegroundColor Cyan
Import-Module Az.Compute
Import-Module Az.Resources
Import-Module Az.StackHCI
Import-Module Az.StackHCIVM

# ============================================================
# Configuration Parameters
# ============================================================
# Azure subscription and resource configuration
$subscriptionId    = "<your subscription ID>"                     # Azure subscription ID
$storagepathname   = "Images"                                     # Name of the HCI storage path resource
$path              = "C:\ClusterStorage\UserStorage_1\Images"     # CSV path on your HCI cluster
$resource_group    = "<cluster resource group>"                   # RG that contains Custom Location & HCI resources
$customLocationName= "<your custom location>"                     # Name of the custom location bound to HCI
$location          = "WestEurope"                                 # Azure region for metadata/management resources
$gallery           = "<your image gallery>"                       # Azure Compute Gallery name
$definition        = "<your image definition>"                    # Image definition name in the gallery
$imgResourceGroup  = "<image resource group>"                     # RG containing the gallery and for temp disk

# ============================================================
# Azure Subscription Context
# ============================================================

# Set the Azure subscription context for all subsequent operations
Write-Host "Setting Azure subscription context..." -ForegroundColor Cyan
Set-AzContext -SubscriptionId $subscriptionId

# ============================================================
# Custom Location Resolution
# ============================================================

# Resolve the Custom Location resource ID
# Custom Location provides the bridge between Azure and the on-premises HCI cluster
Write-Host "Resolving Custom Location resource ID..." -ForegroundColor Cyan
$customLocation = Get-AzResource `
  -ResourceGroupName $resource_group `
  -ResourceType "Microsoft.ExtendedLocation/customLocations" `
  -Name $customLocationName

$customLocationID = $customLocation.ResourceId
Write-Host "Custom Location ID resolved: $customLocationID" -ForegroundColor Green

# ============================================================
# Storage Path Configuration
# ============================================================

# Create the Azure Stack HCI storage path resource (logical pointer to CSV path)
# This registers the on-premises path so images can be stored there by the HCI VM service
Write-Host "Configuring HCI storage path..." -ForegroundColor Cyan

$storagePathProperties = @{
  path = $path
  extendedLocation = @{
    type = "CustomLocation"
    name = $customLocationID
  }
}

try {
  # Attempt to create the storage path resource
  Write-Host "Creating storage path '$storagepathname' at '$path'..." -ForegroundColor Yellow
  $existingStoragePath = Get-AzResource `
    -ResourceGroupName $resource_group `
    -ResourceType "Microsoft.AzureStackHCI/storagecontainers" `
    -Name $storagepathname `
    -Properties $storagePathProperties `
    -Force
  Write-Host "Storage path '$storagepathname' created successfully." -ForegroundColor Green
}
catch {
  # Storage path already exists - this is expected on subsequent runs
  Write-Host "Storage path '$storagepathname' already exists. Skipping creation." -ForegroundColor Yellow
}

# ============================================================
# Image Version Discovery
# ============================================================

# Retrieve the latest (non-excluded) image version from the Azure Compute Gallery
# Filters out any versions marked as ExcludeFromLatest in the gallery publishing profile
Write-Host "Retrieving latest image version from Azure Compute Gallery..." -ForegroundColor Cyan
$sourceImgVer = Get-AzGalleryImageVersion `
  -GalleryImageDefinitionName $definition `
  -GalleryName $gallery `
  -ResourceGroupName $imgResourceGroup |
  Where-Object { $_.PublishingProfile.ExcludeFromLatest -eq $false } |
  Select-Object -Last 1

Write-Host "Found latest image version: $($sourceImgVer.Name)" -ForegroundColor Green

# Check if this image version is already imported in the HCI cluster
# This prevents duplicate imports and saves time/resources
Write-Host "Checking if image already exists in HCI cluster..." -ForegroundColor Cyan
$existingHCIImage = (Get-AZStackHciVMimage -ResourceGroupName $resource_group).name
$normalizedImageName = $sourceImgVer.Name.Replace(".", "-")

if ($existingHCIImage -contains $normalizedImageName) {
    Write-Host "Image version $($sourceImgVer.Name) already exists in HCI. Skipping import." -ForegroundColor Yellow
    Exit
}
Write-Host "Image does not exist in HCI. Proceeding with import..." -ForegroundColor Green


# ============================================================
# Temporary Managed Disk Creation
# ============================================================

# Create a temporary managed disk from the gallery image version
# This disk serves as an intermediary for exporting the image to HCI
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Creating Temporary Managed Disk" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Try {
  # Normalize the image version name for disk naming (replace dots with dashes)
  $diskName = $sourceImgVer.Name.Replace(".", "-")
  
  # Configure the disk to be created from the gallery image
  $diskConfig = New-AzDiskConfig `
    -Location $location `
    -CreateOption FromImage `
    -GalleryImageReference @{Id = $sourceImgVer.Id }

  # Check if the temporary disk already exists from a previous run
  $check = Get-AzDisk `
    -ResourceGroupName $imgResourceGroup `
    -DiskName $diskName `
    -ErrorAction SilentlyContinue
    
  if ($check) {
    Write-Host "Temporary disk '$diskName' already exists. Reusing existing disk." -ForegroundColor Yellow
  }
  else {
    Write-Host "Creating temporary managed disk: $diskName" -ForegroundColor Yellow
    Write-Host "This may take several minutes depending on image size..." -ForegroundColor Yellow
    $tempDisk = New-AzDisk `
      -ResourceGroupName $imgResourceGroup `
      -DiskName $diskName `
      -Disk $diskConfig `
      -ErrorAction Stop

    Write-Host "Successfully created temporary disk: $diskName" -ForegroundColor Green
  }
}
Catch {
  $createError = $_.Exception.Message
  Write-Host "Failed to create temporary disk: $createError" -ForegroundColor Red
  Write-Host "Please verify resource group permissions and disk quota." -ForegroundColor Red
  Exit
}


# ============================================================
# SAS Access Generation
# ============================================================

# Grant read-only SAS (Shared Access Signature) access to the managed disk
# The SAS URL provides secure, time-limited access for the HCI cluster to download the image
# Duration: 8 hours (28800 seconds) - sufficient time for large image transfers
Write-Host "`nGenerating SAS access for disk export..." -ForegroundColor Cyan

try {
  $sasAccess = Grant-AzDiskAccess `
    -ResourceGroupName $imgResourceGroup `
    -DiskName $diskName `
    -Access Read `
    -DurationInSecond 28800

  $imageSourcePath = $sasAccess.AccessSAS
  
  # Validate that the SAS URL was successfully generated
  if ($null -eq $imageSourcePath) {
    Throw "SAS URL generation returned null. Unable to proceed with image import."
  }
  
  Write-Host "Successfully generated SAS URL for disk access" -ForegroundColor Green
  Write-Host "SAS URL valid for 8 hours" -ForegroundColor Green
}
catch {
  $createError = $_.Exception.Message
  Write-Host "Failed to generate SAS URL: $createError" -ForegroundColor Red
  Write-Host "Verify disk exists and you have appropriate permissions." -ForegroundColor Red
  Exit
}


# ============================================================
# HCI Image Import
# ============================================================

# Prepare metadata and configuration for HCI image creation
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Importing Image to HCI Cluster" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Define the OS type for the image (Windows or Linux)
$osType = "Windows"  # Change to "Linux" if importing a Linux-based image
$imageName = $sourceImgVer.Name.Replace(".", "-")

Write-Host "Image Name: $imageName" -ForegroundColor Cyan
Write-Host "OS Type: $osType" -ForegroundColor Cyan

# Retrieve the storage path resource ID where the image will be stored
Write-Host "Resolving storage path resource ID..." -ForegroundColor Cyan
$storagePath = Get-AzResource `
  -ResourceGroupName $resource_group `
  -ResourceType "Microsoft.AzureStackHCI/storagecontainers" `
  -Name $storagepathname

$StoragePathID = $storagePath.ResourceId
Write-Host "Storage Path ID: $StoragePathID" -ForegroundColor Green

# Prepare image properties metadata
$imageProperties = @{
  osType = $osType
  cloudInitDataSource = "NoCloud"
  version = @{
    name = $sourceImgVer.Name
    properties = @{
      storageProfile = @{
        osDiskImage = @{
          sourceUri = $imageSourcePath
        }
      }
    }
  }
  containerName = $storagepathname
  imagePath = $imageSourcePath
  extendedLocation = @{
    type = "CustomLocation"
    name = $customLocationID
  }
}

# Create the HCI VM image resource
# This initiates the download and import process from the SAS URL to the HCI cluster
Write-Host "`nCreating HCI VM image: $imageName" -ForegroundColor Yellow
Write-Host "This process may take 15-30 minutes depending on image size and network speed..." -ForegroundColor Yellow

try {
  New-AZStackHciVMimage `
    -ResourceGroupName $resource_group `
    -CustomLocation $customLocationID `
    -Location $location `
    -Name $imageName `
    -OsType $osType `
    -ImagePath $imageSourcePath `
    -StoragePathId $StoragePathID `
    -ErrorAction Stop
  
  Write-Host "`n========================================" -ForegroundColor Green
  Write-Host "SUCCESS: HCI Image Import Completed!" -ForegroundColor Green
  Write-Host "========================================" -ForegroundColor Green
  Write-Host "Image Name: $imageName" -ForegroundColor Green
  Write-Host "Storage Location: $path" -ForegroundColor Green
  Write-Host "`nThe image is now available for VM deployments on the HCI cluster." -ForegroundColor Cyan
}
catch {
  $importError = $_.Exception.Message
  Write-Host "`nFailed to create HCI image: $importError" -ForegroundColor Red
  Write-Host "Please verify network connectivity between Azure and the HCI cluster." -ForegroundColor Red
  Exit
}

# ============================================================
# Cleanup Recommendation
# ============================================================
Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "CLEANUP RECOMMENDATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "The temporary managed disk '$diskName' can now be cleaned up." -ForegroundColor Yellow
Write-Host "Use the Remove-CustomImages.ps1 script to manage disk and image retention." -ForegroundColor Yellow
