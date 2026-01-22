<#
.SYNOPSIS
    Downloads the latest Azure Local monthly release ISO from Microsoft.

.DESCRIPTION
    This script automatically downloads the latest Azure Local ISO using Microsoft's
    monthly release URL pattern (https://aka.ms/hcireleaseimage/YYMM).
    
    The script:
    - Determines the current year and month
    - Constructs the download URL
    - Checks if the URL is valid
    - Falls back to previous months if current month isn't available yet
    - Downloads the ISO with progress tracking
    - Verifies the downloaded file

.PARAMETER DownloadPath
    The directory where the ISO will be downloaded. Defaults to current directory.

.PARAMETER MaxMonthsBack
    Maximum number of months to check backwards. Defaults to 12 months.

.PARAMETER Force
    Forces re-download even if the ISO already exists.

.PARAMETER SkipVerification
    Skips file verification after download.

.NOTES
    File Name      : Get-LatestAzureLocalRelease.ps1
    Author         : GetToTheCloud
    Prerequisite   : PowerShell 5.1 or higher, Internet connectivity
    Version        : 1.0
    
.EXAMPLE
    .\Get-LatestAzureLocalRelease.ps1
    Downloads the latest Azure Local ISO to the current directory.

.EXAMPLE
    .\Get-LatestAzureLocalRelease.ps1 -DownloadPath "C:\ISOs"
    Downloads the latest ISO to C:\ISOs directory.

.EXAMPLE
    .\Get-LatestAzureLocalRelease.ps1 -MaxMonthsBack 6
    Checks only the last 6 months for available releases.

.LINK
    https://learn.microsoft.com/azure/azure-stack/hci/
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DownloadPath = $PWD.Path,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxMonthsBack = 12,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipVerification
)

#Requires -Version 5.1

# ============================================================
# Configuration
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Base URL pattern for Azure Local monthly releases
$BaseUrlPattern = "https://aka.ms/hcireleaseimage/{0}"

# ============================================================
# Helper Functions
# ============================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$NoNewline
    )
    
    $params = @{
        Object = $Message
        ForegroundColor = $Color
    }
    
    if ($NoNewline) {
        $params.Add("NoNewline", $true)
    }
    
    Write-Host @params
}

function Write-Section {
    param([string]$Title)
    
    Write-Host ""
    Write-ColorOutput "========================================" -Color Cyan
    Write-ColorOutput $Title -Color Cyan
    Write-ColorOutput "========================================" -Color Cyan
}

function Get-ReleaseCode {
    <#
    .SYNOPSIS
        Generates the release code (YYMM) for a given date.
    #>
    param(
        [datetime]$Date
    )
    
    $year = $Date.Year.ToString().Substring(2, 2)  # Last 2 digits of year
    $month = $Date.Month.ToString("00")            # 2-digit month
    
    return "$year$month"
}

function Get-ReleaseDate {
    <#
    .SYNOPSIS
        Converts a release code (YYMM) back to a date.
    #>
    param(
        [string]$ReleaseCode
    )
    
    $year = "20" + $ReleaseCode.Substring(0, 2)
    $month = $ReleaseCode.Substring(2, 2)
    
    return [datetime]::ParseExact("$year-$month-01", "yyyy-MM-dd", $null)
}

function Test-UrlExists {
    <#
    .SYNOPSIS
        Checks if a URL is accessible and returns valid content.
    #>
    param(
        [string]$Url,
        [switch]$FollowRedirect
    )
    
    try {
        # Use HttpClient to efficiently check URL without downloading entire file
        $httpClient = New-Object System.Net.Http.HttpClient
        $httpClient.Timeout = [System.TimeSpan]::FromSeconds(30)
        
        try {
            # Send GET request but only read headers initially
            $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $Url)
            $responseTask = $httpClient.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
            $response = $responseTask.Result
            
            if ($response.IsSuccessStatusCode) {
                $finalUrl = $response.RequestMessage.RequestUri.AbsoluteUri
                
                # Check if it redirected to Bing (invalid)
                if ($finalUrl -match "bing\.com" -or $finalUrl -match "microsoft\.com/en-us/bing") {
                    $response.Dispose()
                    return @{
                        IsValid = $false
                        FinalUrl = $finalUrl
                        StatusCode = [int]$response.StatusCode
                        Reason = "URL redirects to Bing search (invalid link)"
                    }
                }
                
                # Read just the first 8KB to check content type and detect Bing content
                $contentStream = $response.Content.ReadAsStreamAsync().Result
                $buffer = New-Object byte[] 8192
                $bytesRead = $contentStream.Read($buffer, 0, $buffer.Length)
                
                if ($bytesRead -gt 0) {
                    $content = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                    
                    # Check if content contains Bing indicators
                    if ($content -match "Microsoft Bing" -or $content -match "bing\.com" -or $content -match "<title>Bing</title>") {
                        $contentStream.Dispose()
                        $response.Dispose()
                        return @{
                            IsValid = $false
                            FinalUrl = $finalUrl
                            StatusCode = [int]$response.StatusCode
                            Reason = "Content indicates Bing search page (invalid link)"
                        }
                    }
                }
                
                $contentStream.Dispose()
                
                # For aka.ms links, verify it redirects to a valid Microsoft download
                if ($Url -like "*aka.ms*") {
                    if ($finalUrl -like "*microsoft.com*" -or $finalUrl -like "*download.microsoft*" -or $finalUrl -like "*.microsoft.com*") {
                        $response.Dispose()
                        return @{
                            IsValid = $true
                            FinalUrl = $finalUrl
                            StatusCode = [int]$response.StatusCode
                        }
                    }
                    else {
                        $response.Dispose()
                        return @{
                            IsValid = $false
                            FinalUrl = $finalUrl
                            StatusCode = [int]$response.StatusCode
                            Reason = "Redirect URL doesn't point to Microsoft download"
                        }
                    }
                }
                
                $response.Dispose()
                return @{
                    IsValid = $true
                    FinalUrl = $finalUrl
                    StatusCode = [int]$response.StatusCode
                }
            }
            
            $response.Dispose()
            return @{
                IsValid = $false
                StatusCode = [int]$response.StatusCode
            }
        }
        finally {
            $httpClient.Dispose()
        }
    }
    catch {
        return @{
            IsValid = $false
            Error = $_.Exception.Message
        }
    }
}

function Find-LatestAzureLocalRelease {
    <#
    .SYNOPSIS
        Finds the latest available Azure Local release by checking monthly URLs.
    #>
    param(
        [int]$MaxMonthsToCheck = 12
    )
    
    Write-ColorOutput "Searching for latest Azure Local release..." -Color Yellow
    Write-ColorOutput "Checking up to $MaxMonthsToCheck months back from current date" -Color White
    Write-Host ""
    
    $currentDate = Get-Date
    $attempts = @()
    
    for ($i = 0; $i -lt $MaxMonthsToCheck; $i++) {
        # Calculate the date to check
        $checkDate = $currentDate.AddMonths(-$i)
        $releaseCode = Get-ReleaseCode -Date $checkDate
        $checkUrl = $BaseUrlPattern -f $releaseCode
        
        $monthName = $checkDate.ToString("MMMM yyyy")
        
        Write-ColorOutput "  Checking $monthName (code: $releaseCode)... " -Color Cyan -NoNewline
        
        # Test if URL exists
        $urlTest = Test-UrlExists -Url $checkUrl
        
        $attempts += [PSCustomObject]@{
            ReleaseCode = $releaseCode
            Date = $checkDate
            Url = $checkUrl
            IsValid = $urlTest.IsValid
            FinalUrl = $urlTest.FinalUrl
            StatusCode = $urlTest.StatusCode
        }
        
        if ($urlTest.IsValid) {
            Write-ColorOutput "✓ Found!" -Color Green
            Write-Host ""
            Write-ColorOutput "  Latest release found:" -Color Green
            Write-ColorOutput "    Release: $monthName" -Color White
            Write-ColorOutput "    Code: $releaseCode" -Color White
            Write-ColorOutput "    Short URL: $checkUrl" -Color White
            if ($urlTest.FinalUrl -ne $checkUrl) {
                Write-ColorOutput "    Download URL: $($urlTest.FinalUrl)" -Color White
            }
            
            return @{
                Found = $true
                ReleaseCode = $releaseCode
                ReleaseDate = $checkDate
                ReleaseName = $monthName
                Url = $checkUrl
                DownloadUrl = $urlTest.FinalUrl
                MonthsBack = $i
            }
        }
        else {
            Write-ColorOutput "✗ Not available" -Color Red
            if ($urlTest.Error) {
                Write-ColorOutput "    Error: $($urlTest.Error)" -Color DarkGray
            }
        }
    }
    
    # No valid release found
    Write-Host ""
    Write-ColorOutput "  ✗ No valid release found in the last $MaxMonthsToCheck months" -Color Red
    
    return @{
        Found = $false
        Attempts = $attempts
    }
}

function Get-FileSizeString {
    param([long]$Bytes)
    
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes bytes"
    }
}

function Start-FileDownloadWithProgress {
    <#
    .SYNOPSIS
        Downloads a file with progress tracking.
    #>
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    Write-ColorOutput "Starting download..." -Color Yellow
    Write-ColorOutput "  Source: $Url" -Color White
    Write-ColorOutput "  Destination: $OutputPath" -Color White
    Write-Host ""
    
    # Create parent directory if it doesn't exist
    $parentDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    $startTime = Get-Date
    
    try {
        # Check if BITS is available (Windows only)
        if ($PSVersionTable.Platform -eq $null -or $PSVersionTable.Platform -eq "Win32NT") {
            try {
                Write-ColorOutput "  Using BITS (Background Intelligent Transfer Service)" -Color Cyan
                Write-ColorOutput "  This supports resume for interrupted downloads" -Color Cyan
                Write-Host ""
                
                # Use BITS for better performance and resume capability
                $bitsJob = Start-BitsTransfer -Source $Url -Destination $OutputPath -DisplayName "Azure Local ISO Download" -Description "Downloading $Url" -Asynchronous -RetryInterval 60 -RetryTimeout 86400
                
                $lastProgress = -1
                $noProgressCounter = 0
                $lastBytesTransferred = 0
                
                while ($bitsJob.JobState -eq "Transferring" -or $bitsJob.JobState -eq "Connecting" -or $bitsJob.JobState -eq "Queued") {
                    Start-Sleep -Seconds 2
                    $bitsJob = Get-BitsTransfer -JobId $bitsJob.JobId
                    
                    # Check for stalled download
                    if ($bitsJob.BytesTransferred -eq $lastBytesTransferred) {
                        $noProgressCounter++
                        if ($noProgressCounter -gt 300) { # 10 minutes with no progress (300 * 2 seconds)
                            Write-ColorOutput "  ⚠ Download appears stalled. Attempting to resume..." -Color Yellow
                            Resume-BitsTransfer -BitsJob $bitsJob -Asynchronous
                            $noProgressCounter = 0
                        }
                    }
                    else {
                        $noProgressCounter = 0
                        $lastBytesTransferred = $bitsJob.BytesTransferred
                    }
                    
                    if ($bitsJob.BytesTotal -gt 0) {
                        $progress = [math]::Round(($bitsJob.BytesTransferred / $bitsJob.BytesTotal) * 100, 2)
                        
                        if ($progress -ne $lastProgress -or $noProgressCounter % 30 -eq 0) {
                            $downloadedSize = Get-FileSizeString -Bytes $bitsJob.BytesTransferred
                            $totalSize = Get-FileSizeString -Bytes $bitsJob.BytesTotal
                            $remainingBytes = $bitsJob.BytesTotal - $bitsJob.BytesTransferred
                            
                            # Calculate speed and ETA
                            $elapsed = (Get-Date) - $startTime
                            if ($elapsed.TotalSeconds -gt 0 -and $bitsJob.BytesTransferred -gt 0) {
                                $bytesPerSecond = $bitsJob.BytesTransferred / $elapsed.TotalSeconds
                                if ($bytesPerSecond -gt 0) {
                                    $remainingSeconds = $remainingBytes / $bytesPerSecond
                                    $eta = [TimeSpan]::FromSeconds($remainingSeconds)
                                    $speed = Get-FileSizeString -Bytes $bytesPerSecond
                                    
                                    Write-Progress -Activity "Downloading Azure Local ISO" `
                                        -Status "$downloadedSize of $totalSize ($progress%) - $speed/s - ETA: $($eta.ToString('hh\:mm\:ss'))" `
                                        -PercentComplete $progress
                                }
                                else {
                                    Write-Progress -Activity "Downloading Azure Local ISO" `
                                        -Status "$downloadedSize of $totalSize ($progress%)" `
                                        -PercentComplete $progress
                                }
                            }
                            else {
                                Write-Progress -Activity "Downloading Azure Local ISO" `
                                    -Status "$downloadedSize of $totalSize ($progress%)" `
                                    -PercentComplete $progress
                            }
                            
                            $lastProgress = $progress
                        }
                    }
                }
                
                if ($bitsJob.JobState -eq "Transferred") {
                    Complete-BitsTransfer -BitsJob $bitsJob
                    Write-Progress -Activity "Downloading Azure Local ISO" -Completed
                }
                elseif ($bitsJob.JobState -eq "Error") {
                    $errorMsg = $bitsJob.ErrorDescription
                    Remove-BitsTransfer -BitsJob $bitsJob
                    throw "BITS transfer failed: $errorMsg"
                }
                else {
                    Remove-BitsTransfer -BitsJob $bitsJob
                    throw "BITS transfer ended with unexpected state: $($bitsJob.JobState)"
                }
            }
            catch {
                Write-ColorOutput "  ⚠ BITS download failed: $($_.Exception.Message)" -Color Yellow
                Write-ColorOutput "  Falling back to streaming download..." -Color Yellow
                Write-Host ""
                
                # Fall back to streaming download
                $useStreaming = $true
            }
        }
        else {
            $useStreaming = $true
        }
        
        # Use streaming download for non-Windows or if BITS failed (handles large files better than WebClient)
        if ($useStreaming) {
            Write-ColorOutput "  Using HttpClient streaming for large file download" -Color Cyan
            Write-ColorOutput "  This method reliably handles files > 2GB" -Color Cyan
            Write-Host ""
            
            # Use HttpClient for reliable large file downloads
            $httpClient = New-Object System.Net.Http.HttpClient
            $httpClient.Timeout = [System.TimeSpan]::FromHours(24)
            
            try {
                # Get the response
                $response = $httpClient.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
                $response.EnsureSuccessStatusCode()
                
                $totalBytes = $response.Content.Headers.ContentLength
                $totalSize = Get-FileSizeString -Bytes $totalBytes
                
                Write-ColorOutput "  Total size: $totalSize" -Color White
                Write-Host ""
                
                # Create file stream
                $fileStream = [System.IO.File]::Create($OutputPath)
                $contentStream = $response.Content.ReadAsStreamAsync().Result
                
                # Download buffer (1MB chunks)
                $buffer = New-Object byte[] 1048576
                $totalBytesRead = 0
                $lastProgress = -1
                
                while ($true) {
                    $bytesRead = $contentStream.Read($buffer, 0, $buffer.Length)
                    
                    if ($bytesRead -eq 0) {
                        break
                    }
                    
                    $fileStream.Write($buffer, 0, $bytesRead)
                    $totalBytesRead += $bytesRead
                    
                    # Update progress
                    if ($totalBytes -gt 0) {
                        $progress = [math]::Round(($totalBytesRead / $totalBytes) * 100, 2)
                        
                        if ([math]::Abs($progress - $lastProgress) -ge 0.5) {
                            $downloadedSize = Get-FileSizeString -Bytes $totalBytesRead
                            $remainingBytes = $totalBytes - $totalBytesRead
                            
                            # Calculate speed and ETA
                            $elapsed = (Get-Date) - $startTime
                            if ($elapsed.TotalSeconds -gt 0) {
                                $bytesPerSecond = $totalBytesRead / $elapsed.TotalSeconds
                                if ($bytesPerSecond -gt 0) {
                                    $remainingSeconds = $remainingBytes / $bytesPerSecond
                                    $eta = [TimeSpan]::FromSeconds($remainingSeconds)
                                    $speed = Get-FileSizeString -Bytes $bytesPerSecond
                                    
                                    Write-Progress -Activity "Downloading Azure Local ISO" `
                                        -Status "$downloadedSize of $totalSize ($progress%) - $speed/s - ETA: $($eta.ToString('hh\:mm\:ss'))" `
                                        -PercentComplete $progress
                                }
                                else {
                                    Write-Progress -Activity "Downloading Azure Local ISO" `
                                        -Status "$downloadedSize of $totalSize ($progress%)" `
                                        -PercentComplete $progress
                                }
                            }
                            
                            $lastProgress = $progress
                        }
                    }
                }
                
                # Cleanup
                $fileStream.Close()
                $contentStream.Close()
                $response.Dispose()
                
                Write-Progress -Activity "Downloading Azure Local ISO" -Completed
            }
            catch {
                # Cleanup on error
                if ($fileStream) { $fileStream.Close() }
                if ($contentStream) { $contentStream.Close() }
                if ($response) { $response.Dispose() }
                
                throw
            }
            finally {
                $httpClient.Dispose()
            }
        }
        
        $endTime = Get-Date
        $duration = $endTime - $startTime
        
        Write-Host ""
        Write-ColorOutput "  ✓ Download completed successfully!" -Color Green
        Write-ColorOutput "  Duration: $($duration.ToString('hh\:mm\:ss'))" -Color White
        
        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length
            Write-ColorOutput "  File size: $(Get-FileSizeString -Bytes $fileSize)" -Color White
            
            # Calculate average speed
            if ($duration.TotalSeconds -gt 0) {
                $avgSpeed = $fileSize / $duration.TotalSeconds
                Write-ColorOutput "  Average speed: $(Get-FileSizeString -Bytes $avgSpeed)/s" -Color White
            }
            
            return $true
        }
        
        return $false
    }
    catch {
        Write-ColorOutput "  ✗ Download failed: $($_.Exception.Message)" -Color Red
        
        # Cleanup partial download
        if (Test-Path $OutputPath) {
            Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
        }
        
        throw
    }
}

function Test-ISOFile {
    <#
    .SYNOPSIS
        Verifies the downloaded ISO file.
    #>
    param(
        [string]$FilePath
    )
    
    Write-Section "Verifying Downloaded ISO"
    
    # Check if file exists
    if (-not (Test-Path $FilePath)) {
        Write-ColorOutput "  ✗ File not found: $FilePath" -Color Red
        return $false
    }
    
    # Check file size
    $fileInfo = Get-Item $FilePath
    $fileSizeMB = $fileInfo.Length / 1MB
    
    Write-ColorOutput "  File: $($fileInfo.Name)" -Color White
    Write-ColorOutput "  Size: $(Get-FileSizeString -Bytes $fileInfo.Length)" -Color White
    Write-ColorOutput "  Created: $($fileInfo.CreationTime)" -Color White
    Write-ColorOutput "  Modified: $($fileInfo.LastWriteTime)" -Color White
    
    # Azure Local ISOs should be several GB
    if ($fileSizeMB -lt 500) {
        Write-ColorOutput "  ⚠ File size seems too small for Azure Local ISO (< 500 MB)" -Color Yellow
        Write-ColorOutput "  Expected size: 5-10 GB" -Color Yellow
        return $false
    }
    
    # Verify it's actually an ISO file (check for ISO 9660 signature)
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $stream.Seek(0x8000, [System.IO.SeekOrigin]::Begin) | Out-Null
        $buffer = New-Object byte[] 6
        $stream.Read($buffer, 0, 6) | Out-Null
        $stream.Close()
        
        $signature = [System.Text.Encoding]::ASCII.GetString($buffer)
        
        if ($signature -like "*CD001*") {
            Write-ColorOutput "  ✓ Valid ISO 9660 file format detected" -Color Green
        }
        else {
            Write-ColorOutput "  ⚠ ISO signature not found - file may be corrupt" -Color Yellow
            return $false
        }
    }
    catch {
        Write-ColorOutput "  ⚠ Could not verify ISO format: $($_.Exception.Message)" -Color Yellow
    }
    
    Write-ColorOutput "`n  ✓ File appears to be a valid ISO image" -Color Green
    return $true
}

# ============================================================
# Main Script Execution
# ============================================================

try {
    Write-Section "Azure Local Release Downloader"
    
    Write-ColorOutput "Script version: 1.0" -Color White
    Write-ColorOutput "PowerShell version: $($PSVersionTable.PSVersion)" -Color White
    Write-ColorOutput "Current date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Color White
    
    # Show current month release code
    $currentReleaseCode = Get-ReleaseCode -Date (Get-Date)
    Write-ColorOutput "Current release code would be: $currentReleaseCode" -Color Cyan
    
    # Validate download path
    if (-not (Test-Path $DownloadPath)) {
        Write-ColorOutput "Creating download directory: $DownloadPath" -Color Yellow
        New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
    }
    
    # Find latest available release
    Write-Section "Finding Latest Release"
    
    $releaseInfo = Find-LatestAzureLocalRelease -MaxMonthsToCheck $MaxMonthsBack
    
    if (-not $releaseInfo.Found) {
        throw "Could not find any available Azure Local release in the last $MaxMonthsBack months"
    }
    
    # Prepare download
    Write-Section "Download Preparation"
    
    $fileName = "AzureLocal-$($releaseInfo.ReleaseCode).iso"
    $outputPath = Join-Path -Path $DownloadPath -ChildPath $fileName
    
    Write-ColorOutput "  Release: $($releaseInfo.ReleaseName)" -Color White
    Write-ColorOutput "  Release code: $($releaseInfo.ReleaseCode)" -Color White
    Write-ColorOutput "  Download URL: $($releaseInfo.Url)" -Color White
    Write-ColorOutput "  Output file: $fileName" -Color White
    Write-ColorOutput "  Full path: $outputPath" -Color White
    
    if ($releaseInfo.MonthsBack -gt 0) {
        Write-ColorOutput "  ℹ This is $($releaseInfo.MonthsBack) month$(if($releaseInfo.MonthsBack -gt 1){'s'}) old" -Color Cyan
    }
    else {
        Write-ColorOutput "  ℹ This is the current month's release" -Color Green
    }
    
    # Check if file already exists
    if (Test-Path $outputPath) {
        $existingFile = Get-Item $outputPath
        $existingSize = Get-FileSizeString -Bytes $existingFile.Length
        
        Write-Host ""
        Write-ColorOutput "ℹ File already exists:" -Color Cyan
        Write-ColorOutput "  Path: $outputPath" -Color White
        Write-ColorOutput "  Size: $existingSize" -Color White
        Write-ColorOutput "  Modified: $($existingFile.LastWriteTime)" -Color White
        
        if ($Force) {
            Write-ColorOutput "`n  Force parameter specified. Re-downloading..." -Color Yellow
            Remove-Item -Path $outputPath -Force
        }
        else {
            Write-ColorOutput "`n  Use -Force to re-download" -Color Yellow
            
            # Ask user
            $response = Read-Host "`nDo you want to re-download? (y/N)"
            if ($response -eq "y" -or $response -eq "Y") {
                Remove-Item -Path $outputPath -Force
            }
            else {
                Write-ColorOutput "`nℹ Using existing file. Verifying..." -Color Cyan
                
                if (-not $SkipVerification) {
                    $isValid = Test-ISOFile -FilePath $outputPath
                    
                    if ($isValid) {
                        Write-Section "Completion"
                        Write-ColorOutput "  ✓ Existing ISO file is valid" -Color Green
                        Write-ColorOutput "  Location: $outputPath" -Color White
                        exit 0
                    }
                    else {
                        Write-ColorOutput "  ⚠ Existing file may be corrupt. Re-downloading..." -Color Yellow
                        Remove-Item -Path $outputPath -Force
                    }
                }
                else {
                    Write-Section "Completion"
                    Write-ColorOutput "  ✓ Using existing file (verification skipped)" -Color Green
                    Write-ColorOutput "  Location: $outputPath" -Color White
                    exit 0
                }
            }
        }
    }
    
    # Download the ISO
    Write-Section "Downloading Azure Local ISO"
    
    $downloadSuccess = Start-FileDownloadWithProgress -Url $releaseInfo.Url -OutputPath $outputPath
    
    if (-not $downloadSuccess) {
        throw "Download did not complete successfully"
    }
    
    # Verify the download
    if (-not $SkipVerification) {
        $isValid = Test-ISOFile -FilePath $outputPath
        
        if (-not $isValid) {
            throw "Downloaded file verification failed"
        }
    }
    else {
        Write-Host ""
        Write-ColorOutput "⚠ Skipping verification as requested" -Color Yellow
    }
    
    # Success summary
    Write-Section "Download Complete"
    Write-ColorOutput "  ✓ Azure Local ISO downloaded successfully!" -Color Green
    Write-ColorOutput "  Release: $($releaseInfo.ReleaseName) ($($releaseInfo.ReleaseCode))" -Color White
    Write-ColorOutput "  Location: $outputPath" -Color White
    Write-ColorOutput "  Size: $(Get-FileSizeString -Bytes (Get-Item $outputPath).Length)" -Color White
    
    # Show next steps
    Write-Host ""
    Write-ColorOutput "Next Steps:" -Color Cyan
    Write-ColorOutput "  1. Mount the ISO:" -Color White
    Write-ColorOutput "     Mount-DiskImage -ImagePath '$outputPath'" -Color Gray
    Write-Host ""
    Write-ColorOutput "  2. Or create bootable media for installation" -Color White
    Write-Host ""
    Write-ColorOutput "  3. Follow Azure Local deployment guide:" -Color White
    Write-ColorOutput "     https://learn.microsoft.com/azure/azure-stack/hci/deploy/deployment-quickstart" -Color Gray
    Write-Host ""
    Write-ColorOutput "  4. Check release notes for this version:" -Color White
    Write-ColorOutput "     https://learn.microsoft.com/azure/azure-stack/hci/release-information" -Color Gray
    
}
catch {
    Write-Host ""
    Write-ColorOutput "========================================" -Color Red
    Write-ColorOutput "ERROR: Script execution failed" -Color Red
    Write-ColorOutput "========================================" -Color Red
    Write-ColorOutput "Message: $($_.Exception.Message)" -Color Red
    
    if ($_.InvocationInfo.ScriptName) {
        Write-ColorOutput "Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -Color Red
    }
    
    Write-Host ""
    Write-ColorOutput "Troubleshooting:" -Color Yellow
    Write-ColorOutput "  - Ensure you have internet connectivity" -Color White
    Write-ColorOutput "  - Check if Microsoft has changed the URL pattern" -Color White
    Write-ColorOutput "  - Try increasing -MaxMonthsBack parameter" -Color White
    Write-ColorOutput "  - Visit: https://www.microsoft.com/en-us/evalcenter/download-azure-stack-hci" -Color White
    
    exit 1
}
