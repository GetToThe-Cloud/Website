<#PSScriptInfo

.VERSION 2.3

.GUID 47fddca1-0108-4ef3-b7ca-4dff491353a0

.AUTHOR GetToTheCloud

.COMPANYNAME GetToTheCloud

.COPYRIGHT (c) 2026 GetToTheCloud. All rights reserved.

.TAGS AzureLocal HCI Update AzureStackHCI PowerShell ARM

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES Az.Accounts,Az.Resources,Az.StackHCI

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
v2.3 - Added REST API fallback for Start-AzStackHciUpdate and Get-AzStackHciUpdateRun; guarded Invoke-AzStackHciUpdatePrecheck availability check.
v2.2 - Fixed NodeCount property lookup compatibility across Az.StackHCI module versions.
v2.1 - Added cross-subscription discovery and interactive update selection.

.PRIVATEDATA

#>

<#
.SYNOPSIS
    Discovers Azure Local clusters and available updates, then interactively applies a chosen update.

.DESCRIPTION
    Run with no parameters (default Discover mode) to:
      1. Scan all accessible Azure subscriptions for Azure Local clusters
      2. Query available solution updates for each cluster
      3. Present a combined table and prompt you to choose a cluster + update
      4. Run prerequisites, health-check, and apply the update with live progress

    Or pass -ClusterName / -ResourceGroupName to skip discovery and target a specific cluster.

.PARAMETER SubscriptionId
    Limit discovery to one subscription. Defaults to scanning ALL enabled subscriptions.

.PARAMETER ClusterName
    Target a specific cluster by name — skips cross-subscription scan.

.PARAMETER ResourceGroupName
    Resource group of the target cluster. Required with -ClusterName.

.PARAMETER UpdateName
    Specific update name to install. Omit to be prompted interactively.

.PARAMETER MonitorIntervalSeconds
    Polling interval (seconds) while monitoring update progress. Default: 60.

.PARAMETER SkipPrerequisiteCheck
    Skip module installation and authentication checks.

.EXAMPLE
    # Interactive discovery across all subscriptions (default)
    .\Invoke-AzureLocalUpdate.ps1

.EXAMPLE
    # Limit discovery to one subscription
    .\Invoke-AzureLocalUpdate.ps1 -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.EXAMPLE
    # Target a specific cluster — still prompts for update selection
    .\Invoke-AzureLocalUpdate.ps1 -ClusterName "azl-cluster-01" -ResourceGroupName "rg-azlocal"

.EXAMPLE
    # Fully automated — no prompts
    .\Invoke-AzureLocalUpdate.ps1 -ClusterName "azl-cluster-01" -ResourceGroupName "rg-azlocal" -UpdateName "Solution_10.2411.0.24"

.NOTES
    File Name      : Invoke-AzureLocalUpdate.ps1
    Author         : GetToTheCloud
    Prerequisites  : PowerShell 5.1+, Az.Accounts, Az.Resources, Az.StackHCI
    Version        : 2.3
    Required RBAC  : Azure Stack HCI Administrator (or Contributor on the cluster resource)

.LINK
    https://learn.microsoft.com/azure/azure-local/update/about-updates-23h2
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Discover')]
param (
    # Shared / discovery scope
    [Parameter(ParameterSetName = 'Discover')]
    [Parameter(ParameterSetName = 'Azure')]
    [string]$SubscriptionId,

    # Target a specific cluster directly
    [Parameter(ParameterSetName = 'Azure', Mandatory)]
    [string]$ClusterName,

    [Parameter(ParameterSetName = 'Azure', Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(ParameterSetName = 'Azure')]
    [string]$UpdateName,

    # Shared behaviour
    [Parameter()]
    [int]$MonitorIntervalSeconds = 60,

    [Parameter()]
    [switch]$SkipPrerequisiteCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

#region Helpers

function Write-Banner {
    $line = '=' * 72
    Write-Host "`n$line" -ForegroundColor DarkCyan
    Write-Host '  Azure Local Solution Update Manager  v2.3  |  GetToTheCloud' -ForegroundColor Cyan
    Write-Host "$line`n" -ForegroundColor DarkCyan
}
function Write-Step    { param([string]$M) Write-Host "`n[$(Get-Date -F 'HH:mm:ss')] >> $M" -ForegroundColor Cyan }
function Write-Success { param([string]$M) Write-Host "  [OK] $M" -ForegroundColor Green }
function Write-Warn    { param([string]$M) Write-Host "  [WARNING] $M" -ForegroundColor Yellow }
function Write-Fail    { param([string]$M) Write-Host "  [ERROR] $M" -ForegroundColor Red }
function Write-Info    { param([string]$M) Write-Host "  $M" -ForegroundColor Gray }

function Get-ClusterUpdates {
    param([string]$Sub, [string]$Rg, [string]$Name)
    # States that mean the update is already done or not applicable - exclude these
    $excludeStates = @('Installed','Recalled','NotApplicableBySolution','NotApplicableHasSolutionUpgrade','NotApplicable')
    try {
        # WarningAction SilentlyContinue suppresses cross-tenant token warnings that would
        # otherwise be promoted to terminating errors by the global ErrorActionPreference=Stop
        $null = Set-AzContext -SubscriptionId $Sub -WarningAction SilentlyContinue -ErrorAction Stop
        [array]$u = @(Get-AzStackHciUpdate -ClusterName $Name -ResourceGroupName $Rg `
            -WarningAction SilentlyContinue -ErrorAction Stop |
            Where-Object { $_.State -notin $excludeStates } |
            Sort-Object Version -Descending)
        return $u
    } catch {
        Write-Warn "  Update query failed for '$Name': $($_.Exception.Message)"
        return [array]@()
    }
}

function Start-ClusterUpdate {
    param([string]$Sub, [string]$Rg, [string]$ClusterN, [string]$UpdateN)
    if (Get-Command 'Start-AzStackHciUpdate' -ErrorAction SilentlyContinue) {
        return Start-AzStackHciUpdate -ClusterName $ClusterN -ResourceGroupName $Rg `
            -Name $UpdateN -WarningAction SilentlyContinue
    }
    Write-Info "  Start-AzStackHciUpdate not available - falling back to REST API..."
    $path = "/subscriptions/$Sub/resourceGroups/$Rg/providers/Microsoft.AzureStackHCI/clusters/$ClusterN/updates/$UpdateN/apply?api-version=2024-01-01"
    $resp = Invoke-AzRestMethod -Method POST -Path $path
    if ($resp.StatusCode -notin @(200, 202)) {
        throw "REST API call failed (HTTP $($resp.StatusCode)): $($resp.Content)"
    }
    return [PSCustomObject]@{ Name = "REST-accepted($($resp.StatusCode))" }
}

function Get-ClusterUpdateRuns {
    param([string]$Sub, [string]$Rg, [string]$ClusterN, [string]$UpdateN)
    if (Get-Command 'Get-AzStackHciUpdateRun' -ErrorAction SilentlyContinue) {
        return @(Get-AzStackHciUpdateRun -ClusterName $ClusterN -ResourceGroupName $Rg `
            -UpdateName $UpdateN -WarningAction SilentlyContinue)
    }
    $path = "/subscriptions/$Sub/resourceGroups/$Rg/providers/Microsoft.AzureStackHCI/clusters/$ClusterN/updateRuns?api-version=2024-01-01"
    $resp = Invoke-AzRestMethod -Method GET -Path $path
    if ($resp.StatusCode -ne 200) { return @() }
    $items = ($resp.Content | ConvertFrom-Json).value
    if (-not $items) { return @() }
    return @($items | ForEach-Object {
        $p = $_.properties
        [PSCustomObject]@{
            Name       = $_.name
            Properties = [PSCustomObject]@{
                State           = $p.state
                ProgressPercent = if ($p.PSObject.Properties['progressPercent']) { [int]$p.progressPercent } else { 0 }
            }
            SystemData = [PSCustomObject]@{
                CreatedAt = if ($_.PSObject.Properties['systemData'] -and $_.systemData) { $_.systemData.createdAt } else { '' }
            }
        }
    })
}

#endregion

Write-Banner

#region STEP 1 - Prerequisites

Write-Step "Step 1 - Checking prerequisites"

if (-not $SkipPrerequisiteCheck) {

    if ($PSVersionTable.PSVersion -lt [version]'5.1') {
        throw "PowerShell 5.1+ required. Current: $($PSVersionTable.PSVersion). Download: https://aka.ms/powershell"
    }
    Write-Success "PowerShell $($PSVersionTable.PSVersion)"

    foreach ($mod in @('Az.Accounts', 'Az.Resources', 'Az.StackHCI')) {
        $m = Get-Module $mod -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $m) {
            Write-Warn "Module '$mod' not found - installing from PSGallery..."
            Install-Module $mod -Scope CurrentUser -Force -AllowClobber
            $m = Get-Module $mod -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        }
        Import-Module $mod -Force
        Write-Success "$mod $($m.Version)"
    }

    $ctx = Get-AzContext
    if (-not $ctx) {
        Write-Warn "Not authenticated - launching device login..."
        Connect-AzAccount -UseDeviceAuthentication
        $ctx = Get-AzContext
    }
    Write-Success "Authenticated as: $($ctx.Account.Id)"

} else {
    Write-Warn "Skipping prerequisite check (-SkipPrerequisiteCheck)"
}

#endregion

#region STEP 2 - Discover clusters and updates (Discover mode only)

if ($PSCmdlet.ParameterSetName -eq 'Discover') {

    Write-Step "Step 2 - Scanning subscriptions for Azure Local clusters"

    if ($SubscriptionId) {
        $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId)
    } else {
        Write-Info "No -SubscriptionId supplied - scanning all enabled subscriptions..."
        $subscriptions = @(Get-AzSubscription -WarningAction SilentlyContinue | Where-Object { $_.State -eq 'Enabled' })
    }
    Write-Info "Subscriptions to scan: $($subscriptions.Count)"

    $allClusters = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($sub in $subscriptions) {
        try {
            $null = Set-AzContext -SubscriptionId $sub.Id -WarningAction SilentlyContinue -ErrorAction Stop
            $clObjs = @(Get-AzStackHciCluster -WarningAction SilentlyContinue -ErrorAction Stop)
            foreach ($c in $clObjs) {
                $nodeCount = if ($c.PSObject.Properties['NodeCount'])      { $c.NodeCount }
                        elseif ($c.PSObject.Properties['NumberOfNodes'])   { $c.NumberOfNodes }
                        elseif ($c.PSObject.Properties['TotalNodeCount'])  { $c.TotalNodeCount }
                        else { 'N/A' }
                $allClusters.Add([PSCustomObject]@{
                    SubscriptionId   = $sub.Id
                    SubscriptionName = $sub.Name
                    ResourceGroup    = $c.ResourceGroupName
                    ClusterName      = $c.Name
                    Connectivity     = $c.ConnectivityStatus
                    Nodes            = $nodeCount
                })
            }
        } catch {
            Write-Warn "  Could not enumerate clusters in '$($sub.Name)': $_"
        }
    }

    if ($allClusters.Count -eq 0) {
        Write-Fail "No Azure Local clusters found in any accessible subscription."
        exit 1
    }
    Write-Success "Found $($allClusters.Count) cluster(s)"

    Write-Step "Step 3 - Querying available updates for each cluster"

    $menuRows     = [System.Collections.Generic.List[PSCustomObject]]::new()
    $upToDateRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $rowIndex     = 1

    foreach ($cl in $allClusters) {
        Write-Info "  Checking $($cl.ClusterName) ($($cl.SubscriptionName) / $($cl.ResourceGroup))..."
        [array]$updates = @(Get-ClusterUpdates -Sub $cl.SubscriptionId -Rg $cl.ResourceGroup -Name $cl.ClusterName)

        if ($updates.Count -eq 0) {
            $upToDateRows.Add([PSCustomObject]@{
                Cluster       = $cl.ClusterName
                ResourceGroup = $cl.ResourceGroup
                Subscription  = $cl.SubscriptionName
                Connectivity  = $cl.Connectivity
                Status        = 'Up to date'
            })
        } else {
            foreach ($u in $updates) {
                $menuRows.Add([PSCustomObject]@{
                    '#'           = $rowIndex
                    Cluster       = $cl.ClusterName
                    ResourceGroup = $cl.ResourceGroup
                    Subscription  = $cl.SubscriptionName
                    Nodes         = $cl.Nodes
                    Connectivity  = $cl.Connectivity
                    UpdateName    = $u.Name
                    Version       = $u.Version
                    'Size(GB)'    = [math]::Round($u.PackageSizeInMb / 1024, 1)
                    State         = $u.State
                    _SubId        = $cl.SubscriptionId
                })
                $rowIndex++
            }
        }
    }

    # Print results table
    $divider = '-' * 110
    Write-Host ""
    Write-Host $divider -ForegroundColor DarkCyan

    if ($menuRows.Count -gt 0) {
        Write-Host "  CLUSTERS WITH AVAILABLE UPDATES" -ForegroundColor White
        Write-Host $divider -ForegroundColor DarkCyan
        $menuRows |
            Select-Object '#', Cluster, ResourceGroup, Subscription, Nodes, Connectivity, Version, 'Size(GB)', State |
            Format-Table -AutoSize |
            Out-String |
            ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }

    if ($upToDateRows.Count -gt 0) {
        Write-Host "  CLUSTERS UP TO DATE" -ForegroundColor DarkGray
        Write-Host $divider -ForegroundColor DarkGray
        $upToDateRows | Format-Table Cluster, ResourceGroup, Subscription, Connectivity, Status -AutoSize |
            Out-String | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    }

    Write-Host $divider -ForegroundColor DarkCyan

    if ($menuRows.Count -eq 0) {
        Write-Success "All clusters are up to date. Nothing to install."
        exit 0
    }

    # Interactive selection
    $selected = $null
    while (-not $selected) {
        $choice = Read-Host "`n  Enter # to install an update (1-$($menuRows.Count)), or press Enter to exit"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Info "No selection made - exiting."
            exit 0
        }
        if ($choice -match '^\d+$') {
            $selected = $menuRows | Where-Object { $_.'#' -eq [int]$choice }
        }
        if (-not $selected) {
            Write-Warn "  Invalid entry '$choice'. Enter a number from the # column."
        }
    }

    Write-Host ""
    Write-Success "Selected: $($selected.Cluster)  |  Update: $($selected.UpdateName)  |  Version: $($selected.Version)"

    # Promote selection to shared variables
    $ClusterName       = $selected.Cluster
    $ResourceGroupName = $selected.ResourceGroup
    $UpdateName        = $selected.UpdateName
    $SubscriptionId    = $selected._SubId
    $null = Set-AzContext -SubscriptionId $SubscriptionId

} else {
    if ($SubscriptionId) {
        $null = Set-AzContext -SubscriptionId $SubscriptionId
    } else {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }
}

#endregion

#region STEP 3/4 - Cluster health check

Write-Step "Cluster health check"

$cluster = Get-AzStackHciCluster -ResourceGroupName $ResourceGroupName -Name $ClusterName -WarningAction SilentlyContinue
$nodeCount = if ($cluster.PSObject.Properties['NodeCount'])     { $cluster.NodeCount }
        elseif ($cluster.PSObject.Properties['NumberOfNodes'])  { $cluster.NumberOfNodes }
        elseif ($cluster.PSObject.Properties['TotalNodeCount']) { $cluster.TotalNodeCount }
        else { 'N/A' }
Write-Success "Cluster : $($cluster.Name)"
Write-Info "  Provisioning state : $($cluster.ProvisioningState)"
Write-Info "  Connectivity status: $($cluster.ConnectivityStatus)"
Write-Info "  Node count         : $nodeCount"

if ($cluster.ConnectivityStatus -ne 'Connected') {
    throw "Cluster connectivity is '$($cluster.ConnectivityStatus)'. Must be Connected before updating."
}

#endregion

#region STEP 4/5 - Resolve / confirm target update

Write-Step "Resolving target update"

$excludeStates = @('Installed','Recalled','NotApplicableBySolution','NotApplicableHasSolutionUpgrade','NotApplicable')
[array]$allUpdates = @(Get-AzStackHciUpdate -ClusterName $ClusterName -ResourceGroupName $ResourceGroupName -WarningAction SilentlyContinue |
    Where-Object { $_.State -notin $excludeStates } |
    Sort-Object Version -Descending)

if ($allUpdates.Count -eq 0) {
    Write-Success "No updates available for $ClusterName - cluster is up to date."
    exit 0
}

if ($UpdateName) {
    $targetUpdate = $allUpdates | Where-Object { $_.Name -eq $UpdateName }
    if (-not $targetUpdate) { throw "Update '$UpdateName' not found for cluster '$ClusterName'." }
} else {
    # Azure mode without prior selection - prompt
    Write-Host "`n  Available updates for $ClusterName :" -ForegroundColor White
    $idx = 1
    $menu = $allUpdates | ForEach-Object {
        [PSCustomObject]@{
            '#'        = $idx++
            Name       = $_.Name
            Version    = $_.Version
            'Size(GB)' = [math]::Round($_.PackageSizeInMb / 1024, 1)
            State      = $_.State
        }
    }
    $menu | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }

    $pick = $null
    while (-not $pick) {
        $c = Read-Host "  Enter # to install (1-$($menu.Count)), or Enter to exit"
        if ([string]::IsNullOrWhiteSpace($c)) { exit 0 }
        if ($c -match '^\d+$') { $pick = $menu | Where-Object { $_.'#' -eq [int]$c } }
        if (-not $pick) { Write-Warn "  Invalid selection." }
    }
    $targetUpdate = $allUpdates | Where-Object { $_.Name -eq $pick.Name }
}

Write-Success "Target: $($targetUpdate.Name)  v$($targetUpdate.Version)"

#endregion

#region STEP 5/6 - Pre-update health check

Write-Step "Pre-update readiness check"

if (Get-Command 'Invoke-AzStackHciUpdatePrecheck' -ErrorAction SilentlyContinue) {
    try {
        $checks = Invoke-AzStackHciUpdatePrecheck -ClusterName $ClusterName `
            -ResourceGroupName $ResourceGroupName -Name $targetUpdate.Name
        $failed = @($checks | Where-Object { $_.Status -ne 'Success' })
        if ($failed.Count -gt 0) {
            Write-Host "`n  Health check results:" -ForegroundColor White
            $checks | Format-Table Name, Status, Severity, Description -AutoSize
            Write-Warn "$($failed.Count) check(s) did not pass - review above before proceeding."
        } else {
            Write-Success "All pre-update health checks passed"
        }
    } catch {
        Write-Warn "Pre-update health check failed: $_"
    }
} else {
    Write-Warn "Invoke-AzStackHciUpdatePrecheck not available in this module version - skipping"
}

#endregion

#region STEP 6/7 - Confirm and start update

Write-Step "Start update"

$updateDisplay = "$($targetUpdate.Name)  v$($targetUpdate.Version)"

if ($PSCmdlet.ShouldProcess($ClusterName, "Install Azure Local solution update: $updateDisplay")) {
    Write-Info "Starting update: $updateDisplay on $ClusterName ..."
    $updateRun = Start-ClusterUpdate -Sub $SubscriptionId -Rg $ResourceGroupName `
        -ClusterN $ClusterName -UpdateN $targetUpdate.Name
    Write-Success "Update job accepted. Run ID: $($updateRun.Name)"
} else {
    Write-Info "-WhatIf specified - update NOT started."
    exit 0
}

#endregion

#region STEP 7/8 - Monitor progress

Write-Step "Monitoring update progress  (Ctrl+C stops monitoring - update continues in background)"

$startTime      = Get-Date
$terminalStates = @('Succeeded','Failed','Canceled')

while ($true) {
    Start-Sleep -Seconds $MonitorIntervalSeconds

    $run = Get-ClusterUpdateRuns -Sub $SubscriptionId -Rg $ResourceGroupName `
        -ClusterN $ClusterName -UpdateN $targetUpdate.Name |
        Sort-Object { $_.SystemData.CreatedAt } -Descending | Select-Object -First 1

    if ($run) {
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        Write-Host ("  [{0}] State: {1,-15} | Progress: {2,3}% | Elapsed: {3}m" -f `
            (Get-Date -F 'HH:mm:ss'), $run.Properties.State,
            $run.Properties.ProgressPercent, $elapsed) -ForegroundColor White
        if ($run.Properties.State -in $terminalStates) { break }
    } else {
        Write-Info "  Waiting for update run record..."
    }
}

#endregion

#region STEP 8/9 - Post-update validation

Write-Step "Post-update validation"

$finalRun = Get-ClusterUpdateRuns -Sub $SubscriptionId -Rg $ResourceGroupName `
    -ClusterN $ClusterName -UpdateN $targetUpdate.Name |
    Sort-Object { $_.SystemData.CreatedAt } -Descending | Select-Object -First 1

switch ($finalRun.Properties.State) {
    'Succeeded' {
        Write-Success "Update completed successfully!"
        $updated = Get-AzStackHciCluster -ResourceGroupName $ResourceGroupName -Name $ClusterName -WarningAction SilentlyContinue
        Write-Info "  Cluster connectivity: $($updated.ConnectivityStatus)"
    }
    'Failed' {
        Write-Fail "Update FAILED. Run the following to investigate:"
        Write-Info "  Get-AzStackHciUpdateRun -ClusterName '$ClusterName' -ResourceGroupName '$ResourceGroupName' -UpdateName '$($targetUpdate.Name)'"
        exit 1
    }
    'Canceled' {
        Write-Warn "Update was canceled."
        exit 2
    }
}

Write-Host "`n[$(Get-Date -F 'HH:mm:ss')] Done.`n" -ForegroundColor Cyan

#endregion
