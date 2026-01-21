# Azure Stack HCI Custom Image Management

Comprehensive solution for importing and managing custom VM images from Azure Compute Gallery to Azure Stack HCI clusters. This repository provides both manual PowerShell scripts and automated Azure DevOps pipelines for image lifecycle management.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Scripts](#scripts)
- [Azure DevOps Pipelines](#azure-devops-pipelines)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## 🎯 Overview

This solution automates the process of maintaining consistent VM golden images across Azure and on-premises Azure Stack HCI environments. It enables centralized image management through Azure Compute Gallery while providing automated import and cleanup capabilities for HCI clusters.

### Key Capabilities

- ✅ Import latest images from Azure Compute Gallery to HCI
- ✅ Automated image version management
- ✅ Storage optimization through retention policies
- ✅ Support for both Azure CLI and PowerShell workflows
- ✅ Azure DevOps pipeline automation
- ✅ Dry-run and approval gates for safety

## ✨ Features

- **Dual Import Methods**: Choose between Azure CLI or PowerShell-based import
- **Automated Cleanup**: Maintain storage efficiency with configurable retention policies
- **Version Management**: Automatically tracks and imports latest image versions
- **Safety Controls**: Dry-run mode and manual approval gates
- **Comprehensive Logging**: Detailed execution logs and status reporting
- **Flexible Configuration**: Parameterized for multiple environments
- **SAS Token Management**: Secure image transfer with automatic cleanup

## 📦 Prerequisites

### Required Software

- **Azure PowerShell Modules**:
  - `Az.Accounts` (≥ 2.0.0)
  - `Az.Compute` (≥ 4.0.0)
  - `Az.Resources` (≥ 4.0.0)
  - `Az.StackHCI` (≥ 1.0.0)
  - `Az.StackHCIVM` (≥ 1.0.0)

- **Azure CLI** (≥ 2.40.0) - For CLI-based scripts
  - `stack-hci-vm` extension (auto-installed)

### Azure Resources

- Azure Compute Gallery with image definitions
- Azure Stack HCI cluster (22H2 or later)
- Custom Location bound to HCI cluster
- Storage path configured on HCI cluster
- Resource groups for HCI and gallery resources

### Permissions Required

- **Azure Subscription**: Contributor or Custom Role with:
  - `Microsoft.Compute/galleries/read`
  - `Microsoft.Compute/galleries/images/read`
  - `Microsoft.Compute/galleries/images/versions/read`
  - `Microsoft.Compute/disks/read,write,delete`
  - `Microsoft.Compute/disks/beginGetAccess/action`
  - `Microsoft.AzureStackHCI/virtualMachineImages/*`
  - `Microsoft.ExtendedLocation/customLocations/read`

## 🏗️ Architecture

```
Azure Compute Gallery
       ↓
  Image Version
       ↓
Temporary Managed Disk
       ↓
   SAS Token
       ↓
Azure Stack HCI Cluster
       ↓
  VM Deployments
```

### Workflow Overview

1. **Discovery**: Query Azure Compute Gallery for latest image version
2. **Disk Creation**: Create temporary managed disk from gallery image
3. **Access Grant**: Generate time-limited SAS token for disk access
4. **Import**: Download and register image in HCI cluster
5. **Cleanup**: Remove temporary disk and revoke SAS access
6. **Retention**: Manage old image versions based on policy

## 📝 Scripts

### `Get-PSCustomImageFromGallery.ps1`

**Purpose**: Import custom VM images using Azure PowerShell modules.

**Key Features**:
- Pure PowerShell implementation
- Full Az module integration
- Comprehensive error handling
- Detailed progress reporting

**Usage**:
```powershell
# Configure parameters in script
$subscriptionId = "your-subscription-id"
$gallery = "your-gallery-name"
$definition = "your-image-definition"

# Run the script
.\Get-PSCustomImageFromGallery.ps1
```

**Parameters**:
| Parameter | Description | Example |
|-----------|-------------|---------|
| `subscriptionId` | Azure subscription ID | `2a234050-17d0-44a2-9755-08e59607bcd9` |
| `storagepathname` | HCI storage path resource name | `Images` |
| `path` | CSV path on HCI cluster | `C:\ClusterStorage\UserStorage_1\Images` |
| `resource_group` | HCI resource group | `rg-hci-cluster` |
| `customLocationName` | Custom location name | `hci-custom-location` |
| `location` | Azure region | `WestEurope` |
| `gallery` | Azure Compute Gallery name | `acg-golden-images` |
| `definition` | Image definition name | `win11-23h2-avd` |
| `imgResourceGroup` | Gallery resource group | `rg-compute-gallery` |

---

### `Get-CustomImageFromGallery.ps1`

**Purpose**: Import custom VM images using Azure CLI commands.

**Key Features**:
- Azure CLI-based implementation
- Cross-platform compatibility
- Simplified command structure
- JSON output parsing

**Usage**:
```bash
# Configure parameters in script
$gallery = "your-gallery-name"
$definition = "your-image-definition"

# Run the script
.\Get-CustomImageFromGallery.ps1
```

**When to Use**:
- CI/CD pipelines preferring Azure CLI
- Cross-platform environments (Linux, macOS, Windows)
- Simpler command-line automation

---

### `Remove-CustomImages.ps1`

**Purpose**: Cleanup old image versions to maintain storage efficiency.

**Key Features**:
- Configurable retention policy
- Pattern-based image matching
- Asynchronous deletion
- Safe default behavior

**Usage**:
```powershell
# Configure retention policy
$imageToKeep = 3  # Keep 3 most recent images

# Run the script
.\Remove-CustomImages.ps1
```

**Parameters**:
| Parameter | Description | Default |
|-----------|-------------|---------|
| `imageToKeep` | Number of recent images to retain | `3` |
| `subscriptionId` | Azure subscription ID | Required |
| `resource_group` | HCI resource group | Required |
| `gallery` | Gallery name for version lookup | Required |
| `definition` | Image definition name | Required |

**Behavior**:
- Retrieves latest gallery version
- Identifies matching images in HCI
- Keeps N most recent versions
- Deletes older versions asynchronously

## 🔄 Azure DevOps Pipelines

### `azure-pipelines-ps-import-image.yml`

**Purpose**: Automated image import using PowerShell modules.

**Stages**:
1. **ValidateEnvironment**: Verify modules and connectivity
2. **ImportImage**: Execute complete import workflow
3. **Cleanup**: Remove temporary resources
4. **Verification**: Confirm successful import

**Parameters**:
```yaml
environmentName: 'Production'      # Target environment
subscriptionId: '<your-sub-id>'    # Azure subscription
storagePathName: 'Images'          # HCI storage path name
csvPath: 'C:\ClusterStorage\...'   # Physical CSV path
resourceGroup: 'rg-hci-cluster'    # HCI resource group
customLocationName: 'hci-location' # Custom location
location: 'WestEurope'             # Azure region
galleryName: 'acg-golden-images'   # Gallery name
imageDefinition: 'win11-23h2-avd'  # Image definition
imgResourceGroup: 'rg-gallery'     # Gallery resource group
osType: 'Windows'                  # OS type
skipExistingCheck: false           # Skip duplicate check
```

**Trigger**:
- Manual by default
- Optional scheduled runs

**Timeout**: 120 minutes (2 hours)

---

### `azure-pipelines-import-image.yml`

**Purpose**: Automated image import using Azure CLI.

**Stages**:
1. **ValidateEnvironment**: Verify CLI and extensions
2. **ImportImage**: Execute CLI-based import
3. **Cleanup**: Remove temporary disks
4. **Verification**: List imported images

**Parameters**:
```yaml
environmentName: 'Production'
storagePathName: 'Images'
csvPath: 'C:\ClusterStorage\UserStorage_1\Images'
osType: 'Windows'
skipCleanup: false
```

**Use Cases**:
- CLI-preferred environments
- Cross-platform automation
- Simplified command execution

---

### `azure-pipelines-cleanup-images.yml`

**Purpose**: Automated cleanup of old image versions.

**Stages**:
1. **ValidateEnvironment**: Module verification
2. **AnalyzeImages**: Identify deletion candidates
3. **ApprovalGate**: Manual review (optional)
4. **CleanupImages**: Execute deletions
5. **Verification**: Confirm cleanup results

**Parameters**:
```yaml
environmentName: 'Production'      # Environment name
subscriptionId: '<your-sub-id>'    # Azure subscription
resourceGroup: 'rg-hci-cluster'    # HCI resource group
customLocationName: 'hci-location' # Custom location
galleryName: 'acg-golden-images'   # Gallery name
imageDefinition: 'win11-23h2-avd'  # Image definition
imgResourceGroup: 'rg-gallery'     # Gallery resource group
imageToKeep: 3                     # Retention count
dryRun: false                      # Preview mode
requireApproval: true              # Manual approval
```

**Safety Features**:
- ✅ **Dry Run Mode**: Preview without deletions
- ✅ **Manual Approval Gate**: Human verification required
- ✅ **Detailed Analysis**: Shows keep/delete decisions
- ✅ **Error Tolerance**: Continues on individual failures

**Scheduling**:
```yaml
# Optional weekly cleanup on Sunday at 3 AM UTC
schedules:
- cron: "0 3 * * 0"
  displayName: Weekly image cleanup
  branches:
    include:
    - main
  always: true
```

## 🚀 Getting Started

### 1. Clone Repository

```bash
git clone <repository-url>
cd PowerShell-AzureLocal-CustomImage
```

### 2. Install Prerequisites

**PowerShell Modules**:
```powershell
Install-Module -Name Az.Accounts -Force
Install-Module -Name Az.Compute -Force
Install-Module -Name Az.Resources -Force
Install-Module -Name Az.StackHCI -Force
Install-Module -Name Az.StackHCIVM -Force
```

**Azure CLI**:
```bash
# Install Azure CLI (if not already installed)
# Windows: https://aka.ms/installazurecliwindows
# macOS: brew install azure-cli
# Linux: https://docs.microsoft.com/cli/azure/install-azure-cli

# Configure extension auto-install
az config set extension.use_dynamic_install=yes_without_prompt
```

### 3. Configure Scripts

Edit configuration parameters in each script:

```powershell
# Update these values to match your environment
$subscriptionId    = "your-subscription-id"
$resource_group    = "your-hci-resource-group"
$customLocationName= "your-custom-location"
$gallery           = "your-gallery-name"
$definition        = "your-image-definition"
$imgResourceGroup  = "your-gallery-resource-group"
```

### 4. Run Manual Import

**Option A: PowerShell**
```powershell
.\Get-PSCustomImageFromGallery.ps1
```

**Option B: Azure CLI**
```powershell
.\Get-CustomImageFromGallery.ps1
```

### 5. Configure Azure DevOps Pipelines

1. **Create Service Connection**:
   - Navigate to Project Settings → Service connections
   - Create new Azure Resource Manager connection
   - Name it (e.g., "Azure-ServiceConnection")
   - Grant permissions to subscription and resource groups

2. **Import Pipeline**:
   - Go to Pipelines → New Pipeline
   - Select "Azure Repos Git" or your repo location
   - Choose "Existing Azure Pipelines YAML file"
   - Select desired pipeline YAML file
   - Update `azureServiceConnection` variable

3. **Update Variables**:
   ```yaml
   variables:
   - name: azureServiceConnection
     value: 'Your-Service-Connection-Name'
   ```

4. **Configure Parameters**:
   - Update default parameter values
   - Or override during pipeline run

5. **Run Pipeline**:
   - Click "Run pipeline"
   - Review/modify parameters
   - Execute

## ⚙️ Configuration

### Environment-Specific Configuration

Create separate parameter sets for each environment:

**Development**:
```powershell
$resourceGroup = "rg-hci-dev"
$customLocationName = "hci-dev-location"
$imageToKeep = 2
```

**Production**:
```powershell
$resourceGroup = "rg-hci-prod"
$customLocationName = "hci-prod-location"
$imageToKeep = 5
```

### Storage Path Configuration

Ensure storage paths exist on HCI cluster:

```powershell
# Verify CSV path
Get-ClusterSharedVolume | Format-Table Name, SharedVolumeInfo

# Expected structure
C:\ClusterStorage\UserStorage_1\Images\
```

### Retention Policy

Configure image retention based on requirements:

| Scenario | Recommended | Rationale |
|----------|-------------|-----------|
| Development | 2-3 images | Fast iteration, less storage needed |
| Test | 3-4 images | Allow rollback for testing |
| Production | 4-5 images | Safety margin for rollbacks |
| Compliance | 6+ images | Audit trail requirements |

## 💡 Usage Examples

### Example 1: First-Time Import

```powershell
# Step 1: Authenticate
Connect-AzAccount

# Step 2: Set subscription
Set-AzContext -SubscriptionId "your-subscription-id"

# Step 3: Run import
.\Get-PSCustomImageFromGallery.ps1

# Expected output:
# ✓ Image version 1.0.20260120 imported successfully
# ✓ Available at: C:\ClusterStorage\UserStorage_1\Images
```

### Example 2: Automated Daily Import

Configure pipeline schedule:
```yaml
schedules:
- cron: "0 2 * * *"  # 2 AM UTC daily
  displayName: Daily image import
  branches:
    include:
    - main
  always: false  # Only if gallery has updates
```

### Example 3: Manual Cleanup with Dry Run

```powershell
# Step 1: Set dry run mode in pipeline
dryRun: true

# Step 2: Run cleanup pipeline
# Review output showing what would be deleted

# Step 3: If satisfied, run with actual deletion
dryRun: false
requireApproval: true
```

### Example 4: Emergency Image Restoration

```powershell
# If wrong image was deleted, restore from gallery
$oldVersion = "1.0.20260115"

# Modify script to target specific version
$sourceImgVer = Get-AzGalleryImageVersion `
  -GalleryName $gallery `
  -ImageDefinitionName $definition `
  -Name $oldVersion `
  -ResourceGroupName $imgResourceGroup

# Run import script
.\Get-PSCustomImageFromGallery.ps1
```

## 📖 Best Practices

### Image Management

1. **Version Naming**: Use semantic versioning in gallery (e.g., `1.0.20260120`)
2. **Test First**: Import to dev/test before production
3. **Document Changes**: Include change logs in gallery image descriptions
4. **Regular Cleanup**: Schedule weekly cleanup pipelines
5. **Monitor Storage**: Track HCI cluster storage consumption

### Security

1. **SAS Tokens**: Always revoke after use (automated in scripts)
2. **Service Principals**: Use dedicated SP for automation
3. **RBAC**: Grant minimum required permissions
4. **Audit Logs**: Enable Azure Activity Log monitoring
5. **Secrets**: Store sensitive values in Azure Key Vault

### Pipeline Automation

1. **Approval Gates**: Enable for production environments
2. **Notifications**: Configure email alerts for pipeline status
3. **Retention**: Keep pipeline logs for compliance
4. **Testing**: Use dry-run mode for validation
5. **Rollback Plan**: Document rollback procedures

### Storage Optimization

1. **Right-Sizing**: Keep only necessary image versions
2. **Monitoring**: Set up alerts for storage thresholds
3. **Cleanup Schedule**: Weekly or bi-weekly cleanup
4. **Compression**: Ensure images are optimized before upload
5. **Deduplication**: Enable storage deduplication on CSV

## 🔧 Troubleshooting

### Common Issues

#### Issue: "Custom Location not found"

**Symptom**: Error resolving custom location ID

**Solution**:
```powershell
# Verify custom location exists
Get-AzResource -ResourceType "Microsoft.ExtendedLocation/customLocations"

# Check resource group
Get-AzResource -ResourceGroupName "rg-hci-cluster" `
  -ResourceType "Microsoft.ExtendedLocation/customLocations"
```

#### Issue: "Failed to create temporary disk"

**Symptom**: Disk creation fails with quota error

**Solution**:
```powershell
# Check disk quota
Get-AzVMUsage -Location "WestEurope" | Where-Object {$_.Name.Value -eq "disks"}

# Request quota increase or clean up old disks
Get-AzDisk -ResourceGroupName "rg-compute-gallery" | 
  Where-Object {$_.Name -like "*-20260*"} | 
  Remove-AzDisk -Force
```

#### Issue: "SAS URL generation failed"

**Symptom**: Error granting disk access

**Solution**:
```powershell
# Verify disk exists and is ready
Get-AzDisk -ResourceGroupName "rg-compute-gallery" -DiskName "image-name"

# Check disk provisioning state
$disk = Get-AzDisk -ResourceGroupName "rg-compute-gallery" -DiskName "image-name"
$disk.ProvisioningState  # Should be "Succeeded"
```

#### Issue: "Image import hangs"

**Symptom**: Import operation takes too long or appears stuck

**Solution**:
```powershell
# Check network connectivity between Azure and HCI
Test-NetConnection -ComputerName "hci-cluster-node" -Port 443

# Verify SAS URL is accessible
$sasUrl = "https://..."
Invoke-WebRequest -Uri $sasUrl -Method Head

# Check HCI cluster status
Get-ClusterNode | Select-Object Name, State
```

#### Issue: "Module not found"

**Symptom**: PowerShell module errors

**Solution**:
```powershell
# Install missing modules
$modules = @('Az.Accounts', 'Az.Compute', 'Az.Resources', 'Az.StackHCI', 'Az.StackHCIVM')
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Install-Module -Name $module -Force -AllowClobber
    }
}

# Verify installation
Get-Module -ListAvailable -Name Az.*
```

### Debug Mode

Enable verbose logging:

```powershell
# PowerShell script debugging
$VerbosePreference = "Continue"
$DebugPreference = "Continue"

# Azure CLI verbose output
az config set core.output=json
az config set core.only_show_errors=false
```

### Getting Help

1. **Check Logs**: Review pipeline execution logs
2. **Azure Portal**: Verify resource states in portal
3. **Activity Log**: Check Azure Activity Log for operations
4. **Support**: Contact Microsoft Support for HCI issues

## 📚 Additional Resources

### Microsoft Documentation

- [Azure Stack HCI Overview](https://learn.microsoft.com/azure/azure-local/)
- [Azure Compute Gallery](https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery)
- [Custom Locations](https://learn.microsoft.com/azure/azure-arc/platform/conceptual-custom-locations)
- [Az PowerShell Modules](https://learn.microsoft.com/powershell/azure/)
- [Azure CLI Reference](https://learn.microsoft.com/cli/azure/)

### Related Repositories

- [Azure Stack HCI Documentation](https://github.com/MicrosoftDocs/azure-stack-docs)
- [Azure Arc Jumpstart](https://github.com/microsoft/azure_arc)

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Code Standards

- Follow PowerShell best practices
- Include comment-based help for functions
- Add error handling for all external calls
- Update documentation for new features
- Test in dev environment before PR

## 📄 License

This project is licensed under the MIT License - see LICENSE file for details.

## 👥 Authors

- **GetToTheCloud** - *Initial work*

## 🙏 Acknowledgments

- Microsoft Azure Stack HCI team
- Azure PowerShell team
- Community contributors

---

## 📞 Support

For issues and questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review [Azure Stack HCI documentation](https://learn.microsoft.com/azure/azure-local/)
3. Open an issue in this repository
4. Contact Microsoft Support for critical production issues

---

**Last Updated**: January 2026  
**Version**: 1.0.0
