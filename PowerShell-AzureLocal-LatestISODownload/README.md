# Azure Local ISO Downloader

Automatically downloads the latest Azure Local (Azure Stack HCI) ISO from Microsoft's monthly release URLs.

## Overview

This PowerShell script simplifies the process of obtaining the latest Azure Local ISO by:
- Automatically detecting the current month's release
- Intelligently falling back to previous months if the current release isn't available yet
- Validating URLs to ensure they point to actual downloads (not Bing search results)
- Downloading large ISOs (5-10GB) reliably using BITS or HttpClient streaming
- Verifying the downloaded ISO file integrity

## Features

✨ **Smart Release Detection**
- Automatically checks for the latest monthly release using Microsoft's URL pattern
- Falls back up to 12 months to find the most recent available version
- Detects invalid URLs that redirect to Bing search

📦 **Reliable Downloads**
- BITS (Background Intelligent Transfer Service) support on Windows with automatic resume
- HttpClient streaming fallback for large files (>2GB) without memory issues
- Progress tracking with real-time speed and ETA calculations
- Automatic stall detection and recovery

✅ **File Verification**
- ISO 9660 format validation
- File size sanity checks
- Prevents downloading corrupted or incomplete files

## Prerequisites

- **PowerShell**: Version 5.1 or higher
- **Operating System**: Windows (BITS support), macOS/Linux (HttpClient streaming)
- **Internet Connection**: Required for downloading ISOs
- **Disk Space**: At least 10GB free for ISO storage

## Installation

1. Download the script:
```powershell
# Clone the repository or download the script directly
git clone <repository-url>
cd azlocal-powershell-latestisodownload
```

2. Ensure execution policy allows running scripts:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Usage

### Basic Usage

Download the latest ISO to the current directory:
```powershell
.\Get-LatestAzureLocalRelease.ps1
```

### Specify Download Location

Download to a specific directory:
```powershell
.\Get-LatestAzureLocalRelease.ps1 -DownloadPath "C:\ISOs"
```

### Force Re-download

Force re-download even if the file already exists:
```powershell
.\Get-LatestAzureLocalRelease.ps1 -DownloadPath "C:\ISOs" -Force
```

### Limit Search Range

Only check the last 6 months for releases:
```powershell
.\Get-LatestAzureLocalRelease.ps1 -MaxMonthsBack 6
```

### Skip Verification

Skip file verification after download (faster, but not recommended):
```powershell
.\Get-LatestAzureLocalRelease.ps1 -SkipVerification
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-DownloadPath` | String | Current directory | Directory where the ISO will be downloaded |
| `-MaxMonthsBack` | Integer | 12 | Maximum number of months to check backwards |
| `-Force` | Switch | False | Forces re-download even if file exists |
| `-SkipVerification` | Switch | False | Skips file verification after download |

## How It Works

### URL Pattern

Microsoft releases Azure Local ISOs monthly using this URL pattern:
```
https://aka.ms/hcireleaseimage/YYMM
```

Where:
- `YY` = Last 2 digits of the year (e.g., 25 for 2025)
- `MM` = Two-digit month (e.g., 12 for December)

**Example**: `https://aka.ms/hcireleaseimage/2512` = December 2025 release

### Release Detection Logic

1. Generates the current month's release code (e.g., 2601 for January 2026)
2. Checks if the URL is valid by:
   - Sending a lightweight request (only headers + first 8KB)
   - Verifying it doesn't redirect to Bing search
   - Confirming it points to a Microsoft download URL
3. If not found, falls back to the previous month
4. Repeats until a valid release is found or max months reached

### Download Methods

**Windows (BITS)**:
- Uses Background Intelligent Transfer Service
- Supports automatic resume for interrupted downloads
- Monitors for stalled downloads and auto-recovers
- Best for large files on Windows

**Non-Windows / BITS Fallback (HttpClient)**:
- Streams content in 1MB chunks
- Handles files larger than 2GB reliably
- No memory overflow issues
- Shows progress with speed and ETA

## Example Output

```
========================================
Azure Local Release Downloader
========================================
Script version: 1.0
PowerShell version: 7.4.6
Current date: 2026-01-22 10:30:00
Current release code would be: 2601

========================================
Finding Latest Release
========================================
Searching for latest Azure Local release...
Checking up to 12 months back from current date

  Checking January 2026 (code: 2601)... ✗ Not available
  Checking December 2025 (code: 2512)... ✓ Found!

  Latest release found:
    Release: December 2025
    Code: 2512
    Short URL: https://aka.ms/hcireleaseimage/2512
    Download URL: https://software-static.download.prss.microsoft.com/[...]

========================================
Downloading Azure Local ISO
========================================
Starting download...
  Source: https://aka.ms/hcireleaseimage/2512
  Destination: C:\ISOs\AzureLocal-2512.iso

  Using BITS (Background Intelligent Transfer Service)
  This supports resume for interrupted downloads

Downloading Azure Local ISO: 4.23 GB of 8.45 GB (50.06%) - 45.2 MB/s - ETA: 00:01:34

========================================
Download Complete
========================================
  ✓ Azure Local ISO downloaded successfully!
  Release: December 2025 (2512)
  Location: C:\ISOs\AzureLocal-2512.iso
  Size: 8.45 GB

Next Steps:
  1. Mount the ISO:
     Mount-DiskImage -ImagePath 'C:\ISOs\AzureLocal-2512.iso'

  2. Or create bootable media for installation

  3. Follow Azure Local deployment guide:
     https://learn.microsoft.com/azure/azure-stack/hci/deploy/deployment-quickstart

  4. Check release notes for this version:
     https://learn.microsoft.com/azure/azure-stack/hci/release-information
```

## Troubleshooting

### "Stream was too long" Error
**Fixed in latest version** - The script now only reads the first 8KB during URL validation instead of downloading the entire file.

### Download Stops at 2GB
**Fixed in latest version** - Uses HttpClient streaming which reliably handles large files.

### "No valid release found"
- Increase `-MaxMonthsBack` parameter (e.g., `-MaxMonthsBack 24`)
- Check Microsoft's Azure Local evaluation center: https://www.microsoft.com/en-us/evalcenter/download-azure-stack-hci
- Verify your internet connection

### BITS Transfer Fails
The script automatically falls back to HttpClient streaming. If you want to force HttpClient:
- Run the script on a non-Windows platform (macOS/Linux)
- The fallback happens automatically on BITS errors

### File Already Exists
- Use `-Force` to re-download
- Or delete the existing file manually: `Remove-Item "C:\ISOs\AzureLocal-*.iso"`

### Download Stalls
On Windows with BITS, the script automatically detects stalls (no progress for 10 minutes) and attempts to resume. For manual control, you can:
```powershell
# View BITS jobs
Get-BitsTransfer

# Resume a specific job
Resume-BitsTransfer -Name "Azure Local ISO Download"

# Remove stuck jobs
Get-BitsTransfer | Remove-BitsTransfer
```

## Known Issues

- **macOS/Linux**: BITS is not available, so resume capability is limited
- **Proxy environments**: May require additional proxy configuration
- **Slow connections**: Large ISO downloads (5-10GB) may take hours on slow connections

## Requirements for Azure Local Deployment

After downloading the ISO, ensure you have:
- **Physical Hardware**: Azure Stack HCI requires physical servers (no VMs for production)
- **Minimum 4 nodes** for production deployments
- **Network**: 1Gb or faster network adapters
- **Storage**: Local SSD/NVMe drives for Storage Spaces Direct
- **Azure Subscription**: Required for Azure Local registration

## Related Links

- [Azure Stack HCI Documentation](https://learn.microsoft.com/azure/azure-stack/hci/)
- [Azure Local Deployment Guide](https://learn.microsoft.com/azure/azure-stack/hci/deploy/deployment-quickstart)
- [Azure Local Release Notes](https://learn.microsoft.com/azure/azure-stack/hci/release-information)
- [Azure Local Evaluation Center](https://www.microsoft.com/en-us/evalcenter/download-azure-stack-hci)

## Version History

### Version 1.0 (January 2026)
- Initial release
- Smart month-by-month fallback logic
- BITS support with stall detection
- HttpClient streaming for large files
- ISO verification with format validation
- Fixed "Stream was too long" error
- Fixed 2GB download limit

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Author

**GetToTheCloud**

## License

This script is provided as-is without warranty. Use at your own risk.
