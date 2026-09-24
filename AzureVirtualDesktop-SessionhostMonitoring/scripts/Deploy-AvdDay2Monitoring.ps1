<#
.SYNOPSIS
    Deploys the AVD Sessionhosts Monitoring 2.0 package.

.DESCRIPTION
    Deploys the supplemental Data Collection Rule from the Bicep template, associates it
    with the session hosts in a resource group and optionally imports the workbook.

    The Microsoft managed microsoft-avdi-<region> Data Collection Rule is never touched.

.PARAMETER SubscriptionId
    Subscription that holds the monitoring resources and the session hosts.

.PARAMETER MonitoringResourceGroupName
    Resource group for the Data Collection Rule and the optional alert rules.

.PARAMETER SessionHostResourceGroupName
    Resource group that holds the session host virtual machines.

.PARAMETER Location
    Azure region of the session hosts, for example westeurope.

.PARAMETER WorkspaceResourceId
    Resource ID of the Log Analytics workspace used by AVD Insights.

.PARAMETER DeployAlerts
    Also deploy the two log search alerts.

.PARAMETER ActionGroupIds
    Action groups notified by the alerts.

.PARAMETER ImportWorkbook
    Also deploy the workbook as a shared workbook in the monitoring resource group.

.PARAMETER WhatIf
    Runs the deployment in what-if mode and changes nothing.

.EXAMPLE
    .\Deploy-AvdDay2Monitoring.ps1 `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -MonitoringResourceGroupName 'rg-avd-monitoring' `
        -SessionHostResourceGroupName 'rg-avd-sessionhosts' `
        -Location 'westeurope' `
        -WorkspaceResourceId '/subscriptions/.../workspaces/law-avd-prod-weu'

.NOTES
    Requires the Az.Accounts, Az.Resources and Az.Compute modules.
    Tested with PowerShell 7.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $true)][string]$MonitoringResourceGroupName,
    [Parameter(Mandatory = $true)][string]$SessionHostResourceGroupName,
    [Parameter(Mandatory = $true)][string]$Location,
    [Parameter(Mandatory = $true)][string]$WorkspaceResourceId,
    [string]$DcrName,
    [int]$SamplingFrequencyInSeconds = 60,
    [switch]$DeployAlerts,
    [string[]]$ActionGroupIds = @(),
    [int]$InputDelayThresholdMs = 200,
    [switch]$ImportWorkbook,
    [string]$WorkbookDisplayName = 'AVD Sessionhosts Monitoring 2.0'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$templateFile = Join-Path $root 'bicep/main.bicep'
$workbookFile = Join-Path $root 'workbook/avd-sessionhosts-monitoring-2.0.workbook.json'

foreach ($module in 'Az.Accounts', 'Az.Resources', 'Az.Compute') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Module $module is required. Install it with: Install-Module $module -Scope CurrentUser"
    }
}

if (-not (Get-AzContext)) {
    Connect-AzAccount -Subscription $SubscriptionId | Out-Null
}
Set-AzContext -Subscription $SubscriptionId | Out-Null

if (-not $DcrName) {
    $DcrName = "dcr-avd-day2-$Location"
}

Write-Host "Collecting session hosts in $SessionHostResourceGroupName" -ForegroundColor Cyan
$sessionHostNames = @(Get-AzVM -ResourceGroupName $SessionHostResourceGroupName | Select-Object -ExpandProperty Name)
Write-Host ("Found {0} virtual machines" -f $sessionHostNames.Count)

if ($sessionHostNames.Count -eq 0) {
    Write-Warning 'No virtual machines found. The Data Collection Rule is deployed without associations.'
}

$parameters = @{
    monitoringResourceGroupName  = $MonitoringResourceGroupName
    sessionHostResourceGroupName = $SessionHostResourceGroupName
    location                     = $Location
    workspaceResourceId          = $WorkspaceResourceId
    sessionHostNames             = $sessionHostNames
    dcrName                      = $DcrName
    samplingFrequencyInSeconds   = $SamplingFrequencyInSeconds
    deployAlerts                 = [bool]$DeployAlerts
    actionGroupIds               = $ActionGroupIds
    inputDelayThresholdMs        = $InputDelayThresholdMs
}

$deploymentName = "avd-day2-monitoring-{0}" -f (Get-Date -Format 'yyyyMMddHHmmss')

if ($PSCmdlet.ShouldProcess($DcrName, 'Deploy AVD Day 2 monitoring')) {
    Write-Host "Deploying $templateFile" -ForegroundColor Cyan
    $deployment = New-AzSubscriptionDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $templateFile `
        -TemplateParameterObject $parameters

    Write-Host ("Deployment state: {0}" -f $deployment.ProvisioningState) -ForegroundColor Green
    Write-Host ("Data Collection Rule: {0}" -f $deployment.Outputs.dataCollectionRuleId.Value)
}
else {
    Write-Host 'Running what-if' -ForegroundColor Cyan
    Get-AzSubscriptionDeploymentWhatIfResult `
        -Location $Location `
        -TemplateFile $templateFile `
        -TemplateParameterObject $parameters
}

if ($ImportWorkbook -and $PSCmdlet.ShouldProcess($WorkbookDisplayName, 'Deploy workbook')) {
    Write-Host 'Deploying the workbook' -ForegroundColor Cyan
    $workbookJson = Get-Content -Path $workbookFile -Raw
    $workbookName = [guid]::NewGuid().ToString()

    $workbookTemplate = @{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        resources      = @(
            @{
                type       = 'Microsoft.Insights/workbooks'
                apiVersion = '2022-04-01'
                name       = $workbookName
                location   = $Location
                kind       = 'shared'
                properties = @{
                    displayName    = $WorkbookDisplayName
                    serializedData = $workbookJson
                    version        = '1.0'
                    category       = 'workbook'
                    sourceId       = $WorkspaceResourceId
                }
            }
        )
    }

    $templatePath = Join-Path ([System.IO.Path]::GetTempPath()) "avd-day2-workbook-$workbookName.json"
    $workbookTemplate | ConvertTo-Json -Depth 20 | Set-Content -Path $templatePath -Encoding utf8

    try {
        New-AzResourceGroupDeployment `
            -ResourceGroupName $MonitoringResourceGroupName `
            -Name "avd-day2-workbook-$(Get-Date -Format 'yyyyMMddHHmmss')" `
            -TemplateFile $templatePath | Out-Null
        Write-Host "Workbook '$WorkbookDisplayName' deployed" -ForegroundColor Green
    }
    finally {
        Remove-Item -Path $templatePath -ErrorAction SilentlyContinue
    }
}

Write-Host 'Done. Run the queries in queries/validation-queries.kql before you trust the charts.' -ForegroundColor Green
