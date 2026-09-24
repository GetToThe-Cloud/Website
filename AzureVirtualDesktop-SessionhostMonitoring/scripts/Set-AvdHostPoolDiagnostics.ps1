<#
.SYNOPSIS
    Enables all diagnostic log categories on one or more AVD host pools.

.DESCRIPTION
    The WVD* tables only exist when the host pool sends its logs to the Log Analytics
    workspace. This script creates a diagnostic setting with the allLogs category group
    on every host pool in a resource group, or on the host pools you name.

.EXAMPLE
    .\Set-AvdHostPoolDiagnostics.ps1 `
        -ResourceGroupName 'rg-avd-hostpools' `
        -WorkspaceResourceId '/subscriptions/.../workspaces/law-avd-prod-weu'

.NOTES
    Requires the Az.Accounts, Az.Monitor and Az.DesktopVirtualization modules.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$ResourceGroupName,
    [Parameter(Mandatory = $true)][string]$WorkspaceResourceId,
    [string[]]$HostPoolName,
    [string]$DiagnosticSettingName = 'diag-avd-day2'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$hostPools = if ($HostPoolName) {
    $HostPoolName | ForEach-Object { Get-AzWvdHostPool -ResourceGroupName $ResourceGroupName -Name $_ }
}
else {
    Get-AzWvdHostPool -ResourceGroupName $ResourceGroupName
}

if (-not $hostPools) {
    throw "No host pools found in $ResourceGroupName"
}

$logSettings = New-AzDiagnosticSettingLogSettingsObject -Enabled $true -CategoryGroup 'allLogs'

foreach ($pool in $hostPools) {
    if ($PSCmdlet.ShouldProcess($pool.Name, 'Enable diagnostic settings')) {
        New-AzDiagnosticSetting `
            -Name $DiagnosticSettingName `
            -ResourceId $pool.Id `
            -WorkspaceId $WorkspaceResourceId `
            -Log $logSettings | Out-Null

        Write-Host "Diagnostics enabled on $($pool.Name)" -ForegroundColor Green
    }
}
