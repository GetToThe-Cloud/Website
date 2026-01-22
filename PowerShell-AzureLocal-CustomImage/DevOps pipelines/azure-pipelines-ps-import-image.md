# Azure DevOps Pipeline: Import Custom Image to Azure Stack HCI

## Overview

This Azure DevOps pipeline automates the process of importing VM images from an Azure Compute Gallery to an Azure Stack HCI (Azure Local) cluster using PowerShell. The pipeline handles the entire workflow from image discovery to import, cleanup, and verification.

## Pipeline Name

```yaml
PS-Import-HCI-Image-$(Date:yyyyMMdd)-$(Rev:r)
```

## Trigger Configuration

The pipeline is configured for **manual trigger only** by default to prevent unintended executions.

```yaml
trigger: none
```

### Optional Scheduled Trigger

The pipeline includes a commented-out schedule configuration that can be enabled to automatically check for new images:

```yaml
schedules:
- cron: "0 2 * * *"
  displayName: Daily image import check
  branches:
    include:
    - main
  always: false  # Only run if there are changes
```

## Pipeline Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| **environmentName** | string | Target environment (Development/Test/Production) | Production |
| **subscriptionId** | string | Azure Subscription ID | (empty - must be provided) |
| **storagePathName** | string | HCI Storage Path Name | Images |
| **csvPath** | string | Physical CSV path on HCI cluster | C:\ClusterStorage\UserStorage_1\Images |
| **resourceGroup** | string | HCI Resource Group name | (empty - must be provided) |
| **customLocationName** | string | Azure Arc Custom Location name | (empty - must be provided) |
| **location** | string | Azure region | WestEurope |
| **galleryName** | string | Azure Compute Gallery name | (empty - must be provided) |
| **imageDefinition** | string | Image Definition name in the gallery | (empty - must be provided) |
| **imgResourceGroup** | string | Resource Group containing the gallery | (empty - must be provided) |
| **osType** | string | Operating System Type (Windows/Linux) | Windows |
| **skipExistingCheck** | boolean | Skip checking if image already exists | false |

## Variables

```yaml
variables:
- name: azureServiceConnection
  value: ''  # Update with your service connection name
```

⚠️ **Important**: Update the `azureServiceConnection` variable with your Azure DevOps service connection name before running the pipeline.

## Pipeline Architecture

The pipeline consists of **4 stages**:

1. **ValidateEnvironment** - Environment validation and prerequisites check
2. **ImportImage** - Main image import workflow
3. **Cleanup** - Cleanup temporary resources
4. **Verification** - Verify successful image import

## Stage 1: ValidateEnvironment

### Purpose
Validates the execution environment and ensures all prerequisites are met.

### Jobs

#### PreflightChecks

**Pool**: `windows-latest`

##### Steps:

1. **Check PowerShell Version**
   - Displays PowerShell version, OS, and platform information
   - Ensures compatibility with required modules

2. **Verify and Install Required Modules**
   - Checks for required Az PowerShell modules:
     - `Az.Accounts`
     - `Az.Compute`
     - `Az.Resources`
     - `Az.StackHCI`
     - `Az.StackHCIVM`
   - Automatically installs missing modules
   - Exits with error code 1 if installation fails

3. **Verify Azure Connectivity**
   - Tests connection to Azure
   - Displays connected subscription, account, and tenant information

## Stage 2: ImportImage

### Purpose
Executes the main image import workflow from Azure Compute Gallery to Azure Stack HCI.

### Jobs

#### ImportJob

**Pool**: `windows-latest`  
**Timeout**: 120 minutes (2 hours) for large images

##### Steps:

1. **Checkout Repository**
   - Checks out the source repository

2. **Set Azure Subscription Context**
   - Sets the Azure context to the specified subscription
   - Validates the subscription is accessible

3. **Resolve Custom Location** (Output: `customLocationID`)
   - Retrieves the Azure Arc custom location resource ID
   - Validates the custom location exists
   - Stores the ID for use in subsequent steps

4. **Create/Verify Storage Path**
   - Verifies the storage path exists in Azure Stack HCI
   - Checks for resource type: `Microsoft.AzureStackHCI/storagecontainers`
   - Creates storage path if it doesn't exist (with fallback to verification only)

5. **Get Latest Gallery Image Version** (Output: `imageName`, `imageVersion`, `imageId`)
   - Queries the Azure Compute Gallery for the latest image version
   - Filters out images marked as `ExcludeFromLatest`
   - Normalizes the image name (replaces dots with hyphens)
   - Stores image metadata for downstream steps

6. **Check if Image Already Exists in HCI** (Output: `imageExists`)
   - Queries existing images in the HCI cluster
   - Skips import if image already exists (unless `skipExistingCheck` is true)
   - Returns `SucceededWithIssues` if image exists

7. **Create Temporary Managed Disk**
   - **Condition**: Only runs if image doesn't exist in HCI
   - Creates a temporary Azure managed disk from the gallery image
   - Reuses existing disk if found
   - Tracks creation duration for monitoring

8. **Generate SAS URL for Disk** (Output: `imageSourcePath`)
   - **Condition**: Only runs if image doesn't exist in HCI
   - Grants read access to the temporary disk
   - Generates SAS token valid for 8 hours (28,800 seconds)
   - Stores SAS URL as a secret variable

9. **Get Storage Path Resource ID** (Output: `storagePathID`)
   - **Condition**: Only runs if image doesn't exist in HCI
   - Resolves the HCI storage path resource ID
   - Required for the image import operation

10. **Import Image to HCI Cluster**
    - **Condition**: Only runs if image doesn't exist in HCI
    - Executes `New-AzStackHciVMimage` cmdlet
    - Parameters:
      - ResourceGroupName
      - CustomLocation
      - Location
      - Name
      - OsType
      - ImagePath (SAS URL)
      - StoragePathId
    - Tracks import duration
    - Typical duration: 15-30 minutes

## Stage 3: Cleanup

### Purpose
Removes temporary resources created during the import process.

### Jobs

#### CleanupJob

**Pool**: `windows-latest`  
**Depends On**: ImportImage  
**Condition**: succeeded()

**Variables**:
- `imageName`: Retrieved from ImportImage stage
- `imageExists`: Retrieved from ImportImage stage

##### Steps:

1. **Revoke SAS Access**
   - **Condition**: Only if image was imported (imageExists = false)
   - Revokes read access from the temporary disk
   - Logs warning if revocation fails

2. **Delete Temporary Disk**
   - **Condition**: Only if image was imported (imageExists = false)
   - Removes the temporary managed disk using `Remove-AzDisk`
   - Uses `-Force` flag to skip confirmation
   - Logs warning with manual cleanup instructions if deletion fails

## Stage 4: Verification

### Purpose
Verifies the image was successfully imported and provides execution summary.

### Jobs

#### VerifyJob

**Pool**: `windows-latest`  
**Depends On**: ImportImage, Cleanup  
**Condition**: succeeded()

**Variables**:
- `imageName`: Retrieved from ImportImage stage
- `imageVersion`: Retrieved from ImportImage stage

##### Steps:

1. **Verify Image in HCI Cluster**
   - Queries HCI cluster for the imported image
   - Validates image is available
   - Displays image details:
     - Image Name
     - Image Version
     - Resource ID
     - Status
   - Logs warning if image not found (may still be provisioning)

2. **Pipeline Execution Summary**
   - Displays comprehensive execution summary:
     - Environment details
     - Subscription information
     - Image details
     - Storage configuration
     - Gallery configuration
   - Provides next steps for using the image
   - Shows PowerShell verification command

## Prerequisites

### Azure Resources

1. **Azure Compute Gallery**
   - Gallery must exist with at least one image definition
   - Image versions must not be marked as `ExcludeFromLatest`

2. **Azure Stack HCI Cluster**
   - Cluster must be registered with Azure Arc
   - Custom Location must be configured
   - Storage container must be available

3. **Resource Groups**
   - HCI resource group
   - Gallery resource group (can be same or different)

### Azure DevOps

1. **Service Connection**
   - Azure Resource Manager service connection
   - Required permissions (see below)

2. **Agent Pool**
   - Access to Microsoft-hosted `windows-latest` agents
   - Or self-hosted Windows agents with PowerShell 7+

### Permissions

The service principal associated with the Azure service connection requires:

#### On Gallery Resource Group:
- `Reader` (to read gallery images)
- `Disk Contributor` (to create/delete temporary disks)

#### On HCI Resource Group:
- `Azure Stack HCI VM Contributor` (to import images)
- `Reader` (to query custom locations and storage paths)

## Workflow Diagram

```
┌──────────────────────────────┐
│   ValidateEnvironment        │
│  - Check PowerShell Version  │
│  - Install Required Modules  │
│  - Verify Azure Connectivity │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│      ImportImage             │
│  1. Set Subscription Context │
│  2. Resolve Custom Location  │
│  3. Verify Storage Path      │
│  4. Get Latest Image Version │
│  5. Check Existing Images    │
│  6. Create Temp Disk         │◄──┐
│  7. Generate SAS URL         │   │ Conditional
│  8. Get Storage Path ID      │   │ (if not exists)
│  9. Import Image to HCI      │◄──┘
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│        Cleanup               │
│  - Revoke SAS Access         │
│  - Delete Temporary Disk     │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│      Verification            │
│  - Verify Image in HCI       │
│  - Display Summary           │
└──────────────────────────────┘
```

## Usage Examples

### Example 1: Basic Usage

```yaml
# Pipeline parameters
environmentName: Production
subscriptionId: 12345678-1234-1234-1234-123456789abc
resourceGroup: rg-hci-prod
customLocationName: HCI-Prod-Location
galleryName: myGallery
imageDefinition: Win11-Enterprise
imgResourceGroup: rg-gallery-prod
osType: Windows
```

### Example 2: Linux Image Import

```yaml
# Pipeline parameters
environmentName: Development
subscriptionId: 12345678-1234-1234-1234-123456789abc
resourceGroup: rg-hci-dev
customLocationName: HCI-Dev-Location
galleryName: myGallery
imageDefinition: Ubuntu-22-04
imgResourceGroup: rg-gallery-dev
osType: Linux
```

### Example 3: Custom Storage Path

```yaml
# Pipeline parameters
environmentName: Test
subscriptionId: 12345678-1234-1234-1234-123456789abc
resourceGroup: rg-hci-test
customLocationName: HCI-Test-Location
storagePathName: CustomImages
csvPath: C:\ClusterStorage\Volume2\VMImages
galleryName: myGallery
imageDefinition: Win11-Enterprise
imgResourceGroup: rg-gallery-test
osType: Windows
```

## Monitoring and Logging

### Progress Indicators

The pipeline provides detailed progress information:

```
========================================
PowerShell Environment Check
========================================
PowerShell Version: 7.4.0
OS: Microsoft Windows 10.0.22631
Platform: Win32NT

========================================
PowerShell Module Verification
========================================
Checking module: Az.Accounts
  ✓ Found Az.Accounts version 3.0.0

========================================
Image Version Discovery
========================================
Gallery: myGallery
Definition: Win11-Enterprise
Resource Group: rg-gallery-prod

Found latest image version:
  Version: 1.0.0
  Name (normalized): 1-0-0
  Resource ID: /subscriptions/.../imageVersions/1.0.0

========================================
Creating Temporary Managed Disk
========================================
Disk Name: 1-0-0
Source Image: /subscriptions/.../imageVersions/1.0.0
Location: WestEurope

Temporary disk created successfully!
Duration: 3.45 minutes

========================================
Importing Image to HCI Cluster
========================================
Image Name: 1-0-0
OS Type: Windows
Environment: Production

This process may take 15-30 minutes...

========================================
SUCCESS: Image Import Completed!
========================================
Duration: 18.32 minutes
Image '1-0-0' is now available for VM deployments
```

### Log Levels

The pipeline uses Azure DevOps logging commands:

- **Error**: `##vso[task.logissue type=error]` - Causes pipeline failure
- **Warning**: `##vso[task.logissue type=warning]` - Logged but doesn't fail pipeline
- **Info**: Standard `Write-Host` output

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: Service Connection Not Found

**Error Message**:
```
The service connection does not exist or is not valid
```

**Solution**:
1. Update the `azureServiceConnection` variable with the correct service connection name
2. Verify the service connection exists in Azure DevOps project settings
3. Ensure the service connection has not expired

#### Issue 2: Custom Location Not Found

**Error Message**:
```
Failed to resolve Custom Location: The Resource 'Microsoft.ExtendedLocation/customLocations/...' under resource group '...' was not found
```

**Solution**:
1. Verify the custom location name matches exactly (case-sensitive)
2. Ensure the custom location exists in the specified resource group
3. Check service principal has Reader access to the resource group

#### Issue 3: Image Already Exists

**Message**:
```
Image '1-0-0' already exists in HCI cluster
```

**Solution**:
- This is expected behavior when the image has already been imported
- The pipeline skips import steps and completes with `SucceededWithIssues`
- To force reimport:
  1. Manually delete the existing image in HCI
  2. Or set `skipExistingCheck: true` to bypass the check

#### Issue 4: Temporary Disk Creation Timeout

**Error Message**:
```
Failed to create temporary disk: The operation timed out
```

**Solution**:
1. Check Azure service health status
2. Verify quota limits in the subscription
3. Try a different Azure region
4. Increase the job timeout if needed

#### Issue 5: SAS URL Expired

**Error Message**:
```
Failed to import image to HCI: Access denied
```

**Solution**:
- The SAS token is valid for 8 hours
- If import takes longer, increase the duration:
  ```powershell
  -DurationInSecond 43200  # 12 hours
  ```

#### Issue 6: Storage Path Not Found

**Error Message**:
```
Failed to resolve storage path ID: The Resource 'Microsoft.AzureStackHCI/storagecontainers/...' was not found
```

**Solution**:
1. Verify the storage path exists in HCI cluster
2. Check the physical path is accessible: `C:\ClusterStorage\UserStorage_1\Images`
3. Ensure the storage path is registered in Azure

#### Issue 7: Module Installation Failure

**Error Message**:
```
Failed to install Az.StackHCIVM: Unable to install, check internet connectivity
```

**Solution**:
1. Verify agent has internet access
2. Check if PowerShell Gallery is accessible
3. Use self-hosted agent with pre-installed modules
4. Configure agent to use proxy if required

## Performance Considerations

### Duration Estimates

| Operation | Typical Duration | Factors |
|-----------|-----------------|---------|
| Module Installation | 1-3 minutes | First run only, cached afterwards |
| Image Version Discovery | 10-30 seconds | Gallery size, network latency |
| Temporary Disk Creation | 3-10 minutes | Image size, Azure region load |
| SAS URL Generation | 5-15 seconds | - |
| Image Import to HCI | 15-45 minutes | Image size, network bandwidth, HCI load |
| Cleanup | 1-2 minutes | - |
| **Total Pipeline** | **20-60 minutes** | Varies by image size |

### Optimization Tips

1. **Reuse Temporary Disks**
   - The pipeline checks for existing disks before creating new ones
   - Speeds up reruns for the same image version

2. **Parallel Imports**
   - Multiple images can be imported simultaneously using matrix strategy
   - Be mindful of Azure Stack HCI cluster capacity

3. **Regional Proximity**
   - Use gallery in the same region as temporary disk creation
   - Reduces network transfer time

4. **Dedicated Express Route**
   - For frequent imports, consider Express Route between Azure and HCI
   - Significantly reduces import duration

## Cost Implications

### Azure Resources

1. **Temporary Managed Disk**
   - Cost: ~$0.05 - $5.00 per execution
   - Duration: Created and deleted within same pipeline run
   - Size: Matches source image (typically 30-128 GB)

2. **Data Transfer**
   - Egress charges from Azure to on-premises HCI
   - Cost depends on image size and data transfer pricing tier

3. **Azure DevOps**
   - Microsoft-hosted agents: Included in free tier or paid minutes
   - Self-hosted agents: No additional Azure DevOps cost

### Cost Optimization

- **Automatic Cleanup**: Ensures temporary disks are deleted
- **Duplicate Detection**: Prevents redundant imports
- **Manual Trigger**: Prevents accidental executions

## Security Best Practices

### Service Principal Permissions

Use **Least Privilege Principle**:

```
Gallery Resource Group:
  - Reader
  - Disk Contributor (for temporary disk operations only)

HCI Resource Group:
  - Azure Stack HCI VM Contributor
  - Reader
```

### Secret Management

- SAS URLs are marked as secret variables
- Not displayed in pipeline logs
- Automatically revoked after import

### Network Security

- Consider using Azure Private Link for gallery access
- Use VPN or ExpressRoute for HCI connectivity
- Implement network security groups (NSGs) where applicable

### Audit and Compliance

- All operations are logged in Azure Activity Log
- Pipeline execution history maintained in Azure DevOps
- Image imports are auditable through HCI management

## Advanced Configuration

### Multi-Region Deployment

To import images to multiple HCI clusters:

```yaml
strategy:
  matrix:
    WestEurope:
      resourceGroup: 'rg-hci-we'
      customLocationName: 'HCI-WE'
      location: 'WestEurope'
    NorthEurope:
      resourceGroup: 'rg-hci-ne'
      customLocationName: 'HCI-NE'
      location: 'NorthEurope'
```

### Approval Gates

For production environments, add deployment approval:

```yaml
- stage: ImportImage
  dependsOn: ValidateEnvironment
  jobs:
  - deployment: ImportJob
    environment: 'production'  # Requires manual approval
    pool:
      vmImage: 'windows-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          # ... existing steps
```

### Email Notifications

Add notification on completion:

```yaml
- task: SendEmail@1
  displayName: 'Send Completion Email'
  condition: always()
  inputs:
    To: 'team@company.com'
    Subject: 'Image Import $(Agent.JobStatus): $(imageName)'
    Body: |
      Image import pipeline completed.
      
      Status: $(Agent.JobStatus)
      Image: $(imageName)
      Version: $(imageVersion)
      Environment: ${{ parameters.environmentName }}
```

## Integration with CI/CD

### Trigger from Gallery Updates

Use Azure Event Grid to trigger the pipeline when a new image version is published:

1. Create Event Grid subscription on Azure Compute Gallery
2. Configure webhook to Azure DevOps API
3. Automatically trigger image import pipeline

### Chain with VM Deployment

After successful import, trigger VM deployment:

```yaml
- stage: DeployVMs
  dependsOn: Verification
  condition: succeeded()
  jobs:
  - job: TriggerVMDeployment
    steps:
    - task: TriggerPipeline@1
      inputs:
        targetProject: 'MyProject'
        targetPipeline: 'Deploy-VMs-to-HCI'
        targetParameters: |
          imageName=$(imageName)
          imageVersion=$(imageVersion)
```

## Maintenance

### Regular Tasks

1. **Update Service Connection**
   - Renew service principal credentials before expiration
   - Verify permissions are still valid

2. **Module Updates**
   - Keep Az PowerShell modules updated
   - Test with new module versions before production use

3. **Cleanup Old Images**
   - Implement retention policy for HCI images
   - Remove unused image versions to free storage

4. **Monitor Pipeline Performance**
   - Review execution times
   - Identify bottlenecks
   - Optimize based on trends

### Version Control

Track changes to the pipeline:

```bash
git log azure-pipelines-ps-import-image.yml
```

Use branches for testing modifications:

```bash
git checkout -b feature/optimize-import
# Make changes
git push origin feature/optimize-import
```

## Support and Documentation

### Related Resources

- [Azure Stack HCI Documentation](https://learn.microsoft.com/azure/azure-stack/hci/)
- [Azure Compute Gallery](https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery)
- [Az.StackHCIVM Module](https://learn.microsoft.com/powershell/module/az.stackhcivm/)
- [Azure DevOps Pipeline YAML Schema](https://learn.microsoft.com/azure/devops/pipelines/yaml-schema/)

### Getting Help

1. Review pipeline logs for error messages
2. Check Azure Activity Log for resource-level errors
3. Verify HCI cluster health in Azure portal
4. Consult Azure Stack HCI documentation

## Changelog

### Version History

- **v1.0** - Initial release
  - Basic image import functionality
  - Automatic cleanup
  - Verification steps

## Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit pull request with description

## License

This pipeline is provided as-is for use in your Azure DevOps projects.

---

**Last Updated**: January 22, 2026  
**Pipeline Version**: 1.0  
**Compatible with**: Azure Stack HCI 23H2+, Azure DevOps Services/Server 2022+

