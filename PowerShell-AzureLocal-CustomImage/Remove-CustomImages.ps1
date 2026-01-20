<#
.SYNOPSIS
    Removes old custom images from Azure Stack HCI to maintain a specified number of recent images.

.DESCRIPTION
    This script manages custom VM images in Azure Stack HCI by:
    - Retrieving existing images from the HCI cluster
    - Identifying images based on the latest Azure Compute Gallery version
    - Cleaning up old images while keeping a specified number of recent versions
    - Removing temporary resources (managed disks) used during image import
    
    The script helps maintain storage efficiency by automatically pruning older image versions
    while ensuring the most recent images remain available for VM deployments.

.PARAMETER subscriptionId
    The Azure subscription ID where the resources are located.

.PARAMETER resource_group
    The resource group containing the Custom Location and Azure Stack HCI resources.

.PARAMETER customLocationName
    The name of the custom location that is bound to the HCI cluster.

.PARAMETER gallery
    The name of the Azure Compute Gallery containing the source images.

.PARAMETER definition
    The image definition name within the Azure Compute Gallery.

.PARAMETER imgResourceGroup
    The resource group containing the Azure Compute Gallery and temporary disk resources.

.PARAMETER imageToKeep
    The number of most recent images to retain in the HCI cluster. Older images will be deleted.

.NOTES
    File Name      : Remove-CustomImages.ps1
    Author         : GetToTheCloud
    Prerequisite   : Azure PowerShell modules (Az.Accounts, Az.Resources, Az.Compute, Az.StackHCI)
    Version        : 1.0
    
.EXAMPLE
    .\Remove-CustomImages.ps1
    Runs the script with the configured parameters to clean up old HCI images.

.LINK
    https://learn.microsoft.com/azure/azure-local/
#>

#Requires -Modules Az.Accounts, Az.Resources, Az.Compute, Az.StackHCI

# ============================================================
# Configuration Parameters
# ============================================================

$subscriptionId    = "2a234050-17d0-44a2-9755-08e59607bcd9"    # Azure subscription ID
$resource_group    = "<cluster resource group>"                # RG that contains Custom Location & HCI resources
$customLocationName= "<your custom location>"                  # Name of the custom location bound to HCI
$gallery           = "<your image gallery>"                    # Azure Compute Gallery name
$definition        = "<your image definition>"                 # Image definition name in the gallery
$imgResourceGroup  = "<image resource group>"                  # RG containing the gallery and for temp disk
$imageToKeep       = 3                                         # Number of latest images to keep in HCI
# ============================================================
# Main Script Execution
# ============================================================

# Set the Azure subscription context for all subsequent operations
Write-Host "Setting Azure subscription context..." -ForegroundColor Cyan
Set-AzContext -SubscriptionId $subscriptionId

# Resolve the Custom Location resource ID
# Custom Location provides the link between Azure and the on-premises HCI cluster
Write-Host "Resolving Custom Location resource ID..." -ForegroundColor Cyan
$customLocationID = (Get-AzResource -ResourceGroupName $resource_group -ResourceType "Microsoft.ExtendedLocation/customLocations" -Name $customLocationName).ResourceId

# Retrieve all existing VM images currently stored in the HCI cluster
Write-Host "Checking existing HCI images..." -ForegroundColor Cyan
$existingHCIImage = (Get-AZStackHciVMimage -ResourceGroupName $resource_group).name

# Get the latest (non-excluded) image version from the Azure Compute Gallery
# Excludes any versions marked as ExcludeFromLatest in the gallery publishing profile
Write-Host "Retrieving latest image version from Azure Compute Gallery..." -ForegroundColor Cyan
$sourceImgVer = Get-AzGalleryImageVersion -GalleryImageDefinitionName $definition -GalleryName $gallery -ResourceGroupName $imgResourceGroup | Where-Object { $_.PublishingProfile.ExcludeFromLatest -eq $false } | Select-Object -Last 1
Write-Host "Found latest image version: $($sourceImgVer.Name)" -ForegroundColor Green

# ============================================================
# Image Cleanup Logic
# ============================================================

# Create a naming pattern based on the image version (e.g., "1.0.20250115" becomes "1-0")
# This pattern is used to identify all related images in the HCI cluster
$rewrite = $sourceImgVer.Name.Replace(".", "-").split("-")[0..1] -join "-"
Write-Host "Using image pattern: $rewrite*" -ForegroundColor Cyan

# Filter existing HCI images to find those matching the version pattern
$customImages = $existingHCIImage | Where-Object { $_ -like "$rewrite*" }

# Check if the number of images exceeds the retention threshold
If ($customImages.Count -ge $imageToKeep) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Image Cleanup Required" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "The image count to keep ($imageToKeep) has already been reached." -ForegroundColor Yellow
    Write-Host "Currently there are $($customImages.Count) images matching the pattern '$rewrite*' in HCI." -ForegroundColor Yellow
    Write-Host "The images that will remain are: $($($customImages | Select -Last $imageToKeep) -join ', ')." -ForegroundColor Yellow
    
    # Identify the oldest images that exceed the retention count
    $imagesToDelete = $customImages | Select-Object -First ($customImages.Count - $imageToKeep)
    
    if ($imagesToDelete.Count -eq 0) {
        Write-Host "No images to delete." -ForegroundColor Yellow
        return
    }
    
    # Delete each old image asynchronously to avoid blocking
    Write-Host "`nStarting deletion of $($imagesToDelete.Count) old image(s)..." -ForegroundColor Cyan
    foreach ($img in $imagesToDelete) {
        Write-Host "Deleting old HCI image: $img" -ForegroundColor Yellow
        $remove = Remove-AzStackHciVMimage -ResourceGroupName $resource_group -Name $img -Force -NoWait
        Write-Host "Deletion of old HCI image: $img has been initiated" -ForegroundColor Green
    }
    Write-Host "`nImage cleanup initiated successfully!" -ForegroundColor Green
}
else {
    Write-Host "`nImage count ($($customImages.Count)) is within the retention limit ($imageToKeep). No cleanup needed." -ForegroundColor Green
}

# ============================================================
# Script Completion
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Script Execution Completed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

