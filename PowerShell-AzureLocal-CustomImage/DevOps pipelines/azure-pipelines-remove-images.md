# Azure DevOps Pipeline: Remove Old HCI Images

## Overview

This Azure DevOps pipeline automates the cleanup of old custom images from Azure Stack HCI (Azure Local) clusters to maintain storage efficiency and cost optimization. The pipeline intelligently manages image retention by keeping only a specified number of recent versions while safely removing older images.

## Pipeline Name

```yaml
PS-Cleanup-HCI-Images-$(Date:yyyyMMdd)-$(Rev:r)
```

## Purpose

The pipeline addresses common challenges in managing Azure Stack HCI image lifecycle:

- **Storage Optimization** - Prevents storage exhaustion from accumulating old images
- **Cost Management** - Reduces storage costs by removing unused images
- **Automated Maintenance** - Eliminates manual cleanup tasks
- **Retention Compliance** - Enforces consistent retention policies
- **Safety First** - Includes approval gates and dry-run mode to prevent accidental deletions

## Trigger Configuration

The pipeline is configured for **manual trigger only** by default to prevent accidental deletions.

```yaml
trigger: none
```

### Optional Scheduled Trigger

An optional schedule configuration is included (commented out) for automated weekly cleanup:

```yaml
schedules:
- cron: "0 3 * * 0"
  displayName: Weekly image cleanup
  branches:
    include:
    - main
  always: true  # Run even if there are no code changes
```

This schedule runs every Sunday at 3 AM UTC, ensuring regular maintenance without manual intervention.

## Pipeline Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| **environmentName** | string | Target environment (Development/Test/Production) | Production |
| **subscriptionId** | string | Azure subscription ID |  |
| **resourceGroup** | string | HCI resource group name |  |
| **customLocationName** | string | Azure Arc custom location name |  |
| **galleryName** | string | Azure Compute Gallery name |  |
| **imageDefinition** | string | Image definition name in the gallery |  |
| **imgResourceGroup** | string | Resource group containing the gallery |  |
| **imagesToKeep** | number | Number of most recent images to retain | 1 |
| **dryRun** | boolean | Preview mode without actual deletion | false |

### Parameter Details

#### imagesToKeep
This critical parameter controls retention policy:
- **Recommended values**: 
  - Development: 2-3 images
  - Test: 2-3 images
  - Production: 3-5 images
- **Minimum**: 1 (always keep at least the latest)
- **Maximum**: No hard limit, but consider storage constraints

#### dryRun
Safety feature for testing:
- **true**: Shows what would be deleted without making changes
- **false**: Performs actual deletion
- **Best practice**: Always run with `dryRun: true` first

## Variables

```yaml
variables:
- name: azureServiceConnection
  value: 'azl-service-connection'  # Update with your service connection name
```

⚠️ **Important**: Update the `azureServiceConnection` variable with your Azure DevOps service connection name.

## Pipeline Architecture

The pipeline consists of **4 stages**:

```
1. ValidateEnvironment  → Environment validation and module checks
2. AnalyzeImages       → Discover and analyze images for cleanup
3. CleanupImages       → Delete old images (conditional on analysis)
4. Verification        → Verify cleanup success
```

### Stage Flow

```
┌─────────────────────┐
│ ValidateEnvironment │
│  - Check modules    │
│  - Test connection  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   AnalyzeImages     │
│  - Get latest ver   │
│  - List HCI images  │
│  - Identify old     │
└──────────┬──────────┘
           │
           ▼ (if cleanup needed)
┌─────────────────────┐
│   CleanupImages     │
│  - Delete old imgs  │
│  - Track results    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Verification      │
│  - Verify cleanup   │
│  - Show summary     │
└─────────────────────┘
```

## Stage 1: ValidateEnvironment

### Purpose
Validates the execution environment and ensures all prerequisites are met.

### Jobs

#### PreflightChecks

**Pool**: `windows-latest`

##### Steps:

1. **Check PowerShell Version**
   - Displays PowerShell environment information
   - Validates compatibility with required cmdlets

2. **Verify and Install Required Modules**
   - Checks for required modules:
     - `Az.Accounts`
     - `Az.Compute`
     - `Az.Resources`
     - `Az.StackHCI`
     - `Az.StackHCIVM`
   - Automatically installs missing modules
   - Fails pipeline if installation errors occur

3. **Verify Azure Connectivity**
   - Tests Azure authentication
   - Displays subscription, account, and tenant details
   - Ensures service principal has necessary permissions

## Stage 2: AnalyzeImages

### Purpose
Analyzes current HCI images and determines which images should be retained or deleted based on retention policy.

### Jobs

#### ImageAnalysis

**Pool**: `windows-latest`

##### Steps:

1. **Checkout Repository**
   - Ensures access to pipeline configuration

2. **Set Azure Subscription Context**
   ```powershell
   Set-AzContext -SubscriptionId "${{ parameters.subscriptionId }}"
   ```
   - Sets the target subscription for all operations

3. **Resolve Custom Location** (Output: `customLocationID`)
   - Retrieves Azure Arc custom location resource ID
   - Validates the custom location exists
   - Required for HCI image operations

4. **Get Latest Gallery Image Version** (Output: `imageVersion`, `imagePattern`)
   - Queries Azure Compute Gallery for the latest image version
   - Filters out images marked as `ExcludeFromLatest`
   - Creates a pattern for matching related images
   
   **Example**:
   ```
   Image version: 1.0.20250115
   Pattern: 1-0*
   ```

5. **List Current HCI Images** (Output: `imagesToDelete`, `deleteCount`, `cleanupRequired`)
   - Retrieves all images from HCI cluster
   - Filters images matching the version pattern
   - Determines which images exceed retention limit
   - Calculates images to delete and images to keep
   
   **Output Example**:
   ```
   Total images in HCI cluster: 12
   Images matching pattern '1-0*': 5
   Images to keep: 3
   
   ⚠ CLEANUP REQUIRED ⚠
   Number of images to delete: 2
   
   Images that will be KEPT:
     ✓ 1-0-20250115
     ✓ 1-0-20250110
     ✓ 1-0-20250105
   
   Images that will be DELETED:
     ✗ 1-0-20250101
     ✗ 1-0-20241220
   ```

### Key Logic

The pipeline uses pattern matching to identify related image versions:

```powershell
# Convert version "1.0.20250115" to pattern "1-0"
$imagePattern = $sourceImgVer.Name.Replace(".", "-").split("-")[0..1] -join "-"

# Match all images with this pattern
$customImages = $existingHCIImages | Where-Object { $_ -like "$imagePattern*" }

# Keep the most recent ones
$imagesToKeep = $customImages | Select-Object -Last $imagesToKeep

# Delete the oldest ones
$imagesToDelete = $customImages | Select-Object -First ($customImages.Count - $imagesToKeep)
```

## Stage 3: CleanupImages

### Purpose
Deletes old images that exceed the retention policy.

### Condition
Only runs if:
- AnalyzeImages stage succeeded
- `cleanupRequired` is `true` (images exceed retention limit)

### Jobs

#### DeleteImages

**Pool**: `windows-latest`

**Variables**:
- `imagesToDelete`: Comma-separated list from AnalyzeImages stage
- `deleteCount`: Number of images to delete

##### Steps:

1. **Delete Old HCI Images**
   - **Condition**: Only if `dryRun` is `false`
   - Iterates through each image to delete
   - Uses `Remove-AzStackHciVMimage` cmdlet
   - Executes with `-NoWait` for asynchronous deletion
   - Tracks success/failure for each image
   
   **Deletion Process**:
   ```powershell
   foreach ($img in $imagesToDelete) {
     Remove-AzStackHciVMimage `
       -ResourceGroupName "$resourceGroup" `
       -Name $img `
       -Force `
       -NoWait
   }
   ```
   
   **Output**:
   ```
   Deleting image: 1-0-20250101
     ✓ Deletion initiated for: 1-0-20250101
   
   Deleting image: 1-0-20241220
     ✓ Deletion initiated for: 1-0-20241220
   
   ========================================
   Deletion Summary
   ========================================
   ImageName        Status    Timestamp
   ---------        ------    ---------
   1-0-20250101     Initiated 1/22/2026 3:15:22 AM
   1-0-20241220     Initiated 1/22/2026 3:15:28 AM
   
   Successfully initiated: 2
   Failed: 0
   ```

2. **Dry Run - Preview Only**
   - **Condition**: Only if `dryRun` is `true`
   - Displays what would be deleted without making changes
   - Useful for testing and validation
   
   **Output**:
   ```
   ========================================
   DRY RUN MODE - No Changes Made
   ========================================
   
   The following images WOULD BE deleted:
     ✗ 1-0-20250101
     ✗ 1-0-20241220
   
   Total images that would be deleted: 2
   
   ⚠ DRY RUN MODE: No actual deletion performed
   Set 'Dry Run' parameter to 'false' to execute actual deletion
   ```

### Error Handling

The pipeline continues even if individual image deletions fail:

- Successful deletions are logged with ✓
- Failed deletions are logged with ✗ and warning
- Summary shows success/failure counts
- Pipeline completes successfully regardless

## Stage 4: Verification

### Purpose
Verifies the cleanup operation was successful and provides execution summary.

### Condition
Only runs if:
- AnalyzeImages stage succeeded
- CleanupImages stage succeeded
- `cleanupRequired` was `true`

### Jobs

#### VerifyCleanup

**Pool**: `windows-latest`

**Variables**:
- `imagePattern`: Retrieved from AnalyzeImages stage

##### Steps:

1. **Verify Remaining Images**
   - Waits 10 seconds for deletion operations to register
   - Queries HCI cluster for remaining images
   - Validates image count is within retention limit
   - Displays all remaining images matching the pattern
   
   **Output**:
   ```
   ========================================
   Post-Cleanup Verification
   ========================================
   
   Waiting for deletion operations to register...
   
   Remaining images matching pattern '1-0*':
     - 1-0-20250115
     - 1-0-20250110
     - 1-0-20250105
   
   Total remaining images: 3
   
   ✓ Cleanup verification successful
   Image count is within retention limit (3)
   ```

2. **Pipeline Execution Summary**
   - Displays comprehensive summary of execution
   - Shows configuration used
   - Provides next steps and verification commands
   
   **Output**:
   ```
   ========================================
   Pipeline Execution Summary
   ========================================
   Environment: Production
   Subscription: 2a234050-17d0-44a2-9755-08e59607bcd9
   HCI Resource Group: azl-we-rsg-azl-koogaandezaan-01
   Gallery: azlavdimages
   Definition: Win11
   Images to Keep: 3
   Dry Run Mode: False
   ========================================
   
   Next Steps:
   1. Verify remaining images in Azure portal
   2. Monitor HCI storage utilization
   3. Review deletion logs for any failures
   4. Schedule regular cleanup runs
   
   Verification Command:
   Get-AzStackHciVMimage -ResourceGroupName 'azl-we-rsg-azl-koogaandezaan-01'
   ```

## Prerequisites

### Azure Resources

1. **Azure Stack HCI Cluster**
   - Registered with Azure Arc
   - Custom location configured
   - Storage capacity tracking enabled

2. **Azure Compute Gallery**
   - Contains image definitions
   - Image versions published regularly

3. **Resource Groups**
   - HCI resource group
   - Gallery resource group

### Azure DevOps

1. **Service Connection**
   - Azure Resource Manager connection
   - Service principal with required permissions

2. **Agent Pool**
   - Access to Microsoft-hosted `windows-latest` agents
   - Or self-hosted Windows agents with PowerShell 7+

### Permissions

The service principal requires:

#### On HCI Resource Group:
- `Azure Stack HCI VM Contributor` (to delete images)
- `Reader` (to query resources)

#### On Gallery Resource Group:
- `Reader` (to read image versions)

## Usage Examples

### Example 1: Safe Testing with Dry Run

```yaml
# Pipeline parameters
environmentName: Production
subscriptionId: 2a234050-17d0-44a2-9755-08e59607bcd9
resourceGroup: azl-we-rsg-azl-koogaandezaan-01
customLocationName: Koog-aan-de-Zaan
galleryName: azlavdimages
imageDefinition: Win11
imgResourceGroup: azl-we-rsg-avd-image-01
imagesToKeep: 3
dryRun: true  # Preview only - no deletion
```

**Use case**: Test the pipeline before running actual deletion to see what would be removed.

### Example 2: Production Cleanup

```yaml
# Pipeline parameters
environmentName: Production
subscriptionId: 2a234050-17d0-44a2-9755-08e59607bcd9
resourceGroup: azl-we-rsg-azl-koogaandezaan-01
customLocationName: Koog-aan-de-Zaan
galleryName: azlavdimages
imageDefinition: Win11
imgResourceGroup: azl-we-rsg-avd-image-01
imagesToKeep: 5  # Keep more images in production
dryRun: false
```

**Use case**: Production environment with higher retention for safety.

### Example 3: Aggressive Cleanup for Development

```yaml
# Pipeline parameters
environmentName: Development
subscriptionId: 2a234050-17d0-44a2-9755-08e59607bcd9
resourceGroup: azl-we-rsg-azl-dev-01
customLocationName: HCI-Dev
galleryName: devimages
imageDefinition: Win11-Dev
imgResourceGroup: azl-we-rsg-avd-dev-image-01
imagesToKeep: 2  # Keep fewer images in dev
dryRun: false
```

**Use case**: Development environment where storage optimization is prioritized.

### Example 4: Multi-Definition Cleanup

For cleaning up multiple image definitions, create multiple pipeline runs or use a matrix strategy:

```yaml
strategy:
  matrix:
    Win11:
      imageDefinition: 'Win11'
    Win10:
      imageDefinition: 'Win10'
    Ubuntu:
      imageDefinition: 'Ubuntu-22-04'
```

## Workflow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   START PIPELINE                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│               VALIDATE ENVIRONMENT                      │
│  ✓ Check PowerShell version                             │
│  ✓ Verify/Install Az modules                            │
│  ✓ Test Azure connectivity                              │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                ANALYZE IMAGES                           │
│  1. Get latest gallery image version                    │
│  2. List all HCI images                                 │
│  3. Filter by pattern (e.g., "1-0*")                   │
│  4. Compare count vs retention limit                    │
│  5. Identify images to delete                           │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
             ┌───────────────┐
             │ Cleanup       │
             │ Required?     │
             └───┬───────┬───┘
                YES     NO
                 │       │
                 │       └──────────┐
                 ▼                  │
┌─────────────────────────────────┐│
│        CLEANUP IMAGES           ││
│  ┌──────────────────────┐       ││
│  │ Dry Run?             │       ││
│  └───┬──────────────┬───┘       ││
│     YES             NO           ││
│      │               │           ││
│      ▼               ▼           ││
│  ┌────────┐    ┌────────┐       ││
│  │Preview │    │ Delete │       ││
│  │  Only  │    │ Images │       ││
│  └────────┘    └────────┘       ││
└────────────┬────────────────────┘│
             │                      │
             ▼                      │
┌─────────────────────────────────┐│
│        VERIFICATION             ││
│  ✓ Verify remaining images      ││
│  ✓ Display summary              ││
│  ✓ Show next steps              ││
└────────────┬────────────────────┘│
             │                      │
             ▼                      ▼
┌─────────────────────────────────────────────────────────┐
│                   PIPELINE COMPLETE                     │
└─────────────────────────────────────────────────────────┘
```

## Monitoring and Logging

### Log Output Examples

#### Successful Cleanup
```
========================================
Deleting Old HCI Images
========================================

Number of images to delete: 2

Starting deletion process...

Deleting image: 1-0-20250101
  ✓ Deletion initiated for: 1-0-20250101

Deleting image: 1-0-20241220
  ✓ Deletion initiated for: 1-0-20241220

========================================
Deletion Summary
========================================
ImageName        Status    Timestamp
---------        ------    ---------
1-0-20250101     Initiated 1/22/2026 3:15:22 AM
1-0-20241220     Initiated 1/22/2026 3:15:28 AM

Successfully initiated: 2
Failed: 0
```

#### No Cleanup Needed
```
========================================
Current HCI Images Analysis
========================================

Total images in HCI cluster: 8
Images matching pattern '1-0*': 2
Images to keep: 3

✓ No cleanup required
Image count (2) is within retention limit (3)
```

#### Partial Failure
```
Deleting image: 1-0-20250101
  ✓ Deletion initiated for: 1-0-20250101

Deleting image: 1-0-20241220
  ✗ Failed to delete: 1-0-20241220
  Error: The resource is locked

========================================
Deletion Summary
========================================
Successfully initiated: 1
Failed: 1
```

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: No Images Found for Cleanup

**Symptom**:
```
No images found matching pattern '1-0*'
```

**Possible Causes**:
1. Image naming doesn't match expected pattern
2. Wrong gallery or definition specified
3. All images have been excluded from latest

**Solution**:
- Verify gallery name and image definition parameters
- Check image version naming convention
- Review gallery publishing settings

#### Issue 2: All Images Would Be Deleted

**Symptom**:
```
Warning: Image count (1) still exceeds limit (1)
```

**Solution**:
- Increase `imagesToKeep` parameter
- Ensure at least 1 image is always retained
- Pipeline automatically prevents deleting all images

#### Issue 3: Deletion Failed - Resource Locked

**Symptom**:
```
Failed to delete: 1-0-20250101
Error: The resource is locked
```

**Solution**:
1. Check for Azure resource locks
2. Verify no VMs are using the image
3. Ensure image is not marked as protected
4. Remove lock and retry pipeline

#### Issue 4: Custom Location Not Found

**Symptom**:
```
Failed to resolve Custom Location: The Resource 'Microsoft.ExtendedLocation/customLocations/...' was not found
```

**Solution**:
- Verify custom location name (case-sensitive)
- Check custom location exists in correct resource group
- Ensure service principal has read access

#### Issue 5: Permission Denied

**Symptom**:
```
Failed to delete image: Forbidden
```

**Solution**:
- Verify service principal has `Azure Stack HCI VM Contributor` role
- Check role assignment scope includes the resource group
- Ensure no deny assignments are in effect

#### Issue 6: Images Still Showing After Deletion

**Symptom**: Images appear in list even after deletion

**Explanation**: Deletion operations may take time to complete

**Solution**:
- Wait 5-10 minutes for operation to complete
- Check Azure portal for operation status
- Run verification command:
  ```powershell
  Get-AzStackHciVMimage -ResourceGroupName 'your-rg-name'
  ```

## Performance Considerations

### Duration Estimates

| Operation | Typical Duration | Factors |
|-----------|-----------------|---------|
| Module Verification | 1-2 minutes | First run only |
| Image Analysis | 30-60 seconds | Number of images in HCI |
| Image Deletion (per image) | 2-5 minutes | Image size, HCI load |
| Verification | 30 seconds | - |
| **Total Pipeline** | **5-20 minutes** | Depends on images to delete |

### Optimization Tips

1. **Batch Operations**
   - Pipeline deletes images asynchronously with `-NoWait`
   - Multiple deletions occur in parallel

2. **Schedule During Off-Hours**
   - Run cleanup during low-usage periods
   - Recommended: Weekends or early morning

3. **Adjust Retention Based on Usage**
   - Development: Keep fewer images (1-2)
   - Test: Moderate retention (2-3)
   - Production: Higher retention (3-5)

4. **Monitor Storage Growth**
   - Track storage utilization trends
   - Adjust cleanup frequency accordingly

## Cost Implications

### Storage Cost Reduction

Removing old images directly reduces storage costs:

**Example Calculation**:
```
Assumptions:
- Average image size: 50 GB
- HCI storage cost: $0.10/GB/month
- Images removed: 3

Savings per cleanup:
3 images × 50 GB × $0.10/GB = $15/month
Annual savings: $15 × 12 = $180/year
```

### Operational Costs

- **Azure DevOps**: Minimal (hosted agent usage)
- **Execution Time**: 5-20 minutes per run
- **Cost per run**: < $0.10

### ROI Analysis

Running weekly cleanup with 3-5 images removed each time:
- **Cost**: ~$5/year (Azure DevOps usage)
- **Savings**: ~$180-300/year (storage reduction)
- **Net Benefit**: $175-295/year per image definition

## Security Best Practices

### Service Principal Configuration

Use **Least Privilege** access:

```
HCI Resource Group:
  - Azure Stack HCI VM Contributor (delete images only)
  - Reader (query resources)

Gallery Resource Group:
  - Reader (read image versions only)
```

### Audit and Compliance

1. **Track Deletions**
   - All deletions logged in Azure Activity Log
   - Pipeline logs retained in Azure DevOps
   - Execution history available for audit

2. **Approval Process**
   - Consider adding manual validation step for production
   - Document approval in pipeline run

3. **Change Management**
   - Treat cleanup as change management activity
   - Notify stakeholders before running
   - Document retained images

### Rollback Considerations

⚠️ **Important**: Image deletion is **irreversible**

Mitigation strategies:
1. Always use `dryRun: true` first
2. Keep sufficient retention (3-5 in production)
3. Document which images are deleted
4. Can re-import from Azure Compute Gallery if needed

## Advanced Configuration

### Adding Approval Gates

For production environments, add manual approval:

```yaml
- job: WaitForApproval
  displayName: 'Manual Approval Required'
  pool: server
  timeoutInMinutes: 1440  # 24 hours
  steps:
  - task: ManualValidation@0
    inputs:
      instructions: |
        Review images to be deleted in previous stage.
        Approve to proceed with deletion.
```

### Email Notifications

Add notification on completion:

```yaml
- task: SendEmail@1
  condition: always()
  inputs:
    To: 'team@company.com'
    Subject: 'HCI Image Cleanup $(Agent.JobStatus)'
    Body: |
      Pipeline: $(Build.DefinitionName)
      Status: $(Agent.JobStatus)
      Images deleted: $(deleteCount)
      Environment: ${{ parameters.environmentName }}
```

### Multi-Environment Support

Use environment-specific parameters:

```yaml
variables:
- ${{ if eq(parameters.environmentName, 'Production') }}:
  - name: approvalRequired
    value: true
  - name: notificationEmail
    value: 'prod-ops@company.com'
- ${{ if ne(parameters.environmentName, 'Production') }}:
  - name: approvalRequired
    value: false
  - name: notificationEmail
    value: 'dev-team@company.com'
```

### Integration with Import Pipeline

Chain with image import pipeline for complete lifecycle:

```yaml
resources:
  pipelines:
  - pipeline: importPipeline
    source: 'PS-Import-HCI-Image'
    trigger:
      branches:
        include:
        - main

trigger:
  pipelines:
  - pipelineRef: importPipeline
    stages:
    - ImportImage
```

## Maintenance and Best Practices

### Regular Tasks

1. **Review Retention Policy** (Quarterly)
   - Assess if `imagesToKeep` value is appropriate
   - Adjust based on storage utilization
   - Consider business requirements

2. **Audit Cleanup Logs** (Monthly)
   - Review which images were deleted
   - Check for any failures
   - Ensure pattern matching is correct

3. **Test Dry Run** (Before Changes)
   - Always test with `dryRun: true` after pipeline modifications
   - Verify expected behavior

4. **Monitor Storage Savings** (Monthly)
   - Track HCI storage utilization
   - Calculate cost savings
   - Report to stakeholders

### Recommended Schedules

| Environment | Cleanup Frequency | Images to Keep |
|-------------|------------------|----------------|
| Development | Weekly | 1-2 |
| Test | Weekly | 2-3 |
| Production | Bi-weekly or Monthly | 3-5 |

### Version Control

Track pipeline changes:

```bash
git log azure-pipelines-remove-images.yml
```

Use branches for testing:

```bash
git checkout -b feature/adjust-retention
# Modify imagesToKeep default
git commit -am "Adjust production retention to 5 images"
git push origin feature/adjust-retention
```

## Related Pipelines

### Image Lifecycle Management

1. **Import Pipeline** (`azure-pipelines-ps-import-image.yml`)
   - Imports new images from Azure Compute Gallery
   - Run before cleanup to ensure latest images are available

2. **Cleanup Pipeline** (this pipeline)
   - Removes old images based on retention policy
   - Run after imports to maintain storage efficiency

### Recommended Workflow

```
1. Build golden image in Azure
        ↓
2. Publish to Azure Compute Gallery
        ↓
3. Run Import Pipeline
        ↓
4. Deploy VMs from new image
        ↓
5. Run Cleanup Pipeline (remove old)
        ↓
6. Repeat monthly/quarterly
```

## Monitoring Dashboard

### Key Metrics to Track

1. **Storage Utilization**
   - Total storage used by images
   - Storage freed per cleanup run
   - Trend over time

2. **Image Count**
   - Total images in HCI
   - Images per definition
   - Images deleted per run

3. **Pipeline Health**
   - Success rate
   - Failure reasons
   - Average execution time

4. **Cost Savings**
   - Storage cost reduction
   - Operational efficiency gains

### Azure Monitor Query Examples

```kusto
// Track image deletions
AzureActivity
| where OperationNameValue == "MICROSOFT.AZURESTACKHCI/VMIMAGES/DELETE"
| where ResourceGroup == "azl-we-rsg-azl-koogaandezaan-01"
| summarize DeleteCount = count() by bin(TimeGenerated, 1d)
| render timechart

// Storage utilization trends
InsightsMetrics
| where Name == "StorageUsedBytes"
| where Tags contains "hci"
| summarize avg(Val) by bin(TimeGenerated, 1h)
| render timechart
```

## Troubleshooting Decision Tree

```
┌─────────────────────┐
│  Pipeline Fails?    │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────────────┐
│ Check Stage Failed          │
└──┬───────┬──────────┬───────┘
   │       │          │
   │       │          │
   ▼       ▼          ▼
Validate  Analyze   Cleanup
   │       │          │
   │       │          │
   ▼       ▼          ▼
Module   Custom    Delete
Missing  Location  Failed
         Not Found
   │       │          │
   ▼       ▼          ▼
Install  Verify    Check
Manually Name      Locks
```

## Support and Documentation

### Related Resources

- [Azure Stack HCI Documentation](https://learn.microsoft.com/azure/azure-stack/hci/)
- [Azure Compute Gallery](https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery)
- [Az.StackHCIVM Module](https://learn.microsoft.com/powershell/module/az.stackhcivm/)
- [Remove-AzStackHciVMimage Cmdlet](https://learn.microsoft.com/powershell/module/az.stackhcivm/remove-azstackhcivmimage)
- [Azure DevOps Pipeline YAML Schema](https://learn.microsoft.com/azure/devops/pipelines/yaml-schema/)

### Getting Help

1. Review pipeline execution logs
2. Check Azure Activity Log for resource operations
3. Verify HCI cluster health in Azure portal
4. Consult Azure Stack HCI documentation
5. Contact Azure support if issues persist

## FAQ

### Q: What happens if I set imagesToKeep to 0?

**A**: The pipeline logic ensures at least 1 image is always retained. Setting to 0 would be overridden to keep 1 image minimum.

### Q: Can I recover deleted images?

**A**: No, image deletion is permanent. However, you can re-import from Azure Compute Gallery if needed.

### Q: How long do deleted images take to free storage?

**A**: Storage is freed immediately, but Azure portal may take 5-10 minutes to reflect changes.

### Q: Can I delete images from multiple definitions at once?

**A**: Yes, use a matrix strategy to run the pipeline for multiple image definitions in parallel.

### Q: What if two versions have the same date but different times?

**A**: The pipeline uses version names to determine order. Latest version by name is retained.

### Q: Does this delete images from Azure Compute Gallery?

**A**: No, only images in Azure Stack HCI cluster are deleted. Gallery images remain unchanged.

### Q: Can I schedule different retention policies for different days?

**A**: Yes, create multiple schedules with different `imagesToKeep` parameters.

### Q: What if the gallery doesn't have the latest version?

**A**: The pipeline queries the gallery but operates independently. It deletes based on existing HCI images.

## Changelog

### Version History

- **v1.0** - Initial release
  - Basic cleanup functionality
  - Dry run mode
  - Pattern-based image matching
  - Retention policy enforcement

## Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Test changes with `dryRun: true`
4. Submit pull request with detailed description

## License

This pipeline is provided as-is for use in your Azure DevOps projects.

---

**Last Updated**: January 22, 2026  
**Pipeline Version**: 1.0  
**Compatible with**: Azure Stack HCI 23H2+, Azure DevOps Services/Server 2022+

