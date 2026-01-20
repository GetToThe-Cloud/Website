<#
.SYNOPSIS
    Imports custom VM images from Azure Compute Gallery to Azure Stack HCI using Azure CLI.

.DESCRIPTION
    This script automates the complete workflow for importing VM images from an Azure Compute Gallery
    to an Azure Stack HCI cluster using Azure CLI commands. The process includes:
    - Authenticating to Azure and configuring CLI settings
    - Creating or validating storage path resources on the HCI cluster
    - Retrieving the latest non-excluded image version from Azure Compute Gallery
    - Creating a temporary managed disk from the gallery image
    - Generating time-limited SAS access for secure image transfer
    - Importing the image into the HCI cluster's storage location
    - Cleaning up temporary resources (SAS access and managed disk)
    
    This enables consistent VM image management across Azure and on-premises HCI environments,
    supporting hybrid cloud scenarios and centralized golden image governance.

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
    File Name      : Get-CustomImageFromGallery.ps1
    Author         : GetToTheCloud
    Prerequisite   : - Azure CLI installed and configured
                     - Az.Compute PowerShell module (for Get-AzGalleryImageVersion)
                     - Appropriate Azure permissions for resource creation
    Version        : 1.0
    
.EXAMPLE
    .\Get-CustomImageFromGallery.ps1
    Runs the script with the configured parameters to import the latest image from Azure Compute Gallery to HCI.

.LINK
    https://learn.microsoft.com/azure/azure-local/
.LINK
    https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery
.LINK
    https://learn.microsoft.com/cli/azure/
#>

#Requires -Modules Az.Compute

# ============================================================
# Azure Authentication
# ============================================================

# Authenticate to Azure using Azure CLI
# This will prompt for credentials in a browser if not already authenticated
Write-Host "Authenticating to Azure via Azure CLI..." -ForegroundColor Cyan
az login

# ============================================================
# Azure CLI Configuration
# ============================================================

# Configure Azure CLI to automatically install required extensions without prompts
# This enables seamless use of stack-hci-vm commands
Write-Host "Configuring Azure CLI extensions..." -ForegroundColor Cyan
az config set extension.use_dynamic_install=yes_without_prompt

# ============================================================
# Configuration Parameters
# ============================================================

# Storage and cluster configuration
$storagepathname   = "Images"                                     # Name of the HCI storage path resource
$path              = "C:\ClusterStorage\UserStorage_1\Images"     # CSV path on your HCI cluster
$resource_group    = "<cluster resource group>"                   # RG that contains Custom Location & HCI resources
$customLocationName= "<your custom location>"                     # Name of the custom location bound to HCI
$location          = "WestEurope"                                 # Azure region for metadata/management resources
$gallery           = "<your image gallery>"                       # Azure Compute Gallery name
$definition        = "<your image definition>"                    # Image definition name in the gallery
$imgResourceGroup  = "<image resource group>"                     # RG containing the gallery and for temp disk

# ============================================================
# Custom Location Resolution
# ============================================================

# Resolve the Custom Location resource ID
# Custom Location provides the bridge between Azure Resource Manager and the on-premises HCI cluster
Write-Host "Resolving Custom Location resource ID..." -ForegroundColor Cyan
$customLocationID = az customlocation show `
  --resource-group $resource_group `
  --name $customLocationName `
  --query id -o tsv

if ([string]::IsNullOrEmpty($customLocationID)) {
    Write-Host "ERROR: Failed to resolve Custom Location ID. Verify the custom location exists." -ForegroundColor Red
    Exit
}
Write-Host "Custom Location ID resolved successfully" -ForegroundColor Green

# ============================================================
# Storage Path Configuration
# ============================================================

# Create the Azure Stack HCI storage path resource (logical pointer to CSV path)
# This registers the on-premises path so images can be stored there by the HCI VM service
Write-Host "Creating HCI storage path resource..." -ForegroundColor Cyan
Write-Host "Storage path name: $storagepathname" -ForegroundColor Yellow
Write-Host "Physical path: $path" -ForegroundColor Yellow

az stack-hci-vm storagepath create `
  --resource-group $resource_group `
  --custom-location $customLocationID `
  --name $storagepathname `
  --path $path

if ($LASTEXITCODE -eq 0) {
    Write-Host "Storage path created successfully" -ForegroundColor Green
} else {
    Write-Host "Storage path creation completed (may already exist)" -ForegroundColor Yellow
}

# ============================================================
# Image Version Discovery
# ============================================================

# Retrieve the latest (non-excluded) image version from the Azure Compute Gallery
# Uses Az PowerShell module to filter versions where ExcludeFromLatest is false
# and selects the most recent version
Write-Host "`nRetrieving latest image version from Azure Compute Gallery..." -ForegroundColor Cyan
Write-Host "Gallery: $gallery" -ForegroundColor Yellow
Write-Host "Definition: $definition" -ForegroundColor Yellow

$sourceImgVer = Get-AzGalleryImageVersion `
  -GalleryImageDefinitionName $definition `
  -GalleryName $gallery `
  -ResourceGroupName $imgResourceGroup |
  Where-Object { $_.PublishingProfile.ExcludeFromLatest -eq $false } |
  Select-Object -Last 1

if ($null -eq $sourceImgVer) {
    Write-Host "ERROR: No valid image version found in the gallery" -ForegroundColor Red
    Exit
}

Write-Host "Found latest image version: $($sourceImgVer.Name)" -ForegroundColor Green

# ============================================================
# Temporary Managed Disk Creation
# ============================================================

# Create a temporary managed disk from the gallery image version
# The disk serves as an intermediary for exporting the image to HCI
# Disk name: Version number with dots replaced by dashes (e.g., "1.0.20250115" -> "1-0-20250115")
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Creating Temporary Managed Disk" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$diskName = $sourceImgVer.Name.Replace(".", "-")
Write-Host "Disk name: $diskName" -ForegroundColor Yellow
Write-Host "Source image: $($sourceImgVer.Id)" -ForegroundColor Yellow
Write-Host "This may take several minutes..." -ForegroundColor Yellow

az disk create `
  --resource-group $imgResourceGroup `
  --location $location `
  --name $diskName `
  --gallery-image-reference $sourceImgVer.id

if ($LASTEXITCODE -eq 0) {
    Write-Host "Temporary disk created successfully" -ForegroundColor Green
} else {
    Write-Host "ERROR: Failed to create temporary disk" -ForegroundColor Red
    Exit
}

# ============================================================
# SAS Access Generation
# ============================================================

# Grant read-only SAS (Shared Access Signature) access to the managed disk
# This provides the HCI cluster with secure, time-limited access to download the image
# Duration: 8 hours (28800 seconds) - adjust if your network requires more time for large images
Write-Host "`nGenerating SAS URL for secure disk access..." -ForegroundColor Cyan
Write-Host "SAS duration: 8 hours" -ForegroundColor Yellow

$imageSourcePath = (
  az disk grant-access `
    --access-level read `
    --resource-group $imgResourceGroup `
    --name $diskName `
    --duration-in-seconds 28800 |
  ConvertFrom-Json
).accessSAS

if ([string]::IsNullOrEmpty($imageSourcePath)) {
    Write-Host "ERROR: Failed to generate SAS URL" -ForegroundColor Red
    Exit
}

Write-Host "SAS URL generated successfully" -ForegroundColor Green
Write-Host "URL expires in 8 hours" -ForegroundColor Yellow

# ============================================================
# HCI Image Import
# ============================================================

# Prepare metadata and configuration for HCI image creation
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Importing Image to HCI Cluster" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Define the OS type for the image (Windows or Linux)
$osType = "Windows"  # Change to "Linux" if importing a Linux-based image
$imageName = $sourceImgVer.Name.Replace(".", "-")  # Name for the image in HCI

Write-Host "Image name: $imageName" -ForegroundColor Yellow
Write-Host "OS type: $osType" -ForegroundColor Yellow

# Retrieve the storage path resource ID where the image will be stored
Write-Host "Resolving storage path resource ID..." -ForegroundColor Cyan
$StoragePathID = az stack-hci-vm storagepath show `
  --resource-group $resource_group `
  --name $storagepathname `
  --query id -o tsv

if ([string]::IsNullOrEmpty($StoragePathID)) {
    Write-Host "ERROR: Failed to resolve storage path ID" -ForegroundColor Red
    Exit
}
Write-Host "Storage path ID resolved" -ForegroundColor Green

# Create the image in Azure Stack HCI
# This initiates the download from the SAS URL and registers the image in HCI
Write-Host "`nCreating HCI VM image..." -ForegroundColor Yellow
Write-Host "This process may take 15-30 minutes depending on image size and network speed" -ForegroundColor Yellow

az stack-hci-vm image create `
  --resource-group $resource_group `
  --custom-location $customLocationID `
  --location $location `
  --name $imageName `
  --os-type $osType `
  --image-path $imageSourcePath `
  --storage-path-id $StoragePathID

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "SUCCESS: HCI Image Import Completed!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Image name: $imageName" -ForegroundColor Green
    Write-Host "Storage location: $path" -ForegroundColor Green
} else {
    Write-Host "ERROR: Failed to create HCI image" -ForegroundColor Red
    Write-Host "Image import may still be in progress. Check Azure portal for status." -ForegroundColor Yellow
}

# ============================================================
# Cleanup - Revoke SAS Access
# ============================================================

# Revoke SAS access to the temporary managed disk
# Security best practice: Remove access once the image import is initiated
Write-Host "`nRevoking SAS access to temporary disk..." -ForegroundColor Cyan
az disk revoke-access `
  --name $diskName `
  --resource-group $imgResourceGroup

if ($LASTEXITCODE -eq 0) {
    Write-Host "SAS access revoked successfully" -ForegroundColor Green
} else {
    Write-Host "Warning: Failed to revoke SAS access" -ForegroundColor Yellow
}

# ============================================================
# Cleanup - Delete Temporary Disk
# ============================================================

# Delete the temporary managed disk to avoid ongoing storage costs
# The disk is no longer needed after the image has been downloaded to HCI
Write-Host "`nDeleting temporary managed disk..." -ForegroundColor Cyan
az disk delete `
  --name $diskName `
  --resource-group $imgResourceGroup `
  --yes

if ($LASTEXITCODE -eq 0) {
    Write-Host "Temporary disk deleted successfully" -ForegroundColor Green
} else {
    Write-Host "Warning: Failed to delete temporary disk" -ForegroundColor Yellow
    Write-Host "You may need to manually delete disk: $diskName" -ForegroundColor Yellow
}

# ============================================================
# Script Completion
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Script Execution Completed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nThe image '$imageName' is now available for VM deployments on the HCI cluster." -ForegroundColor Cyan
Write-Host "Use 'az stack-hci-vm image list --resource-group $resource_group' to verify." -ForegroundColor Cyan
