[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ResourceGroupName,
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $WorkspaceResourceId,
    [string] $Location = "westeurope",
    [string] $DcrName = "dcr-azurelocal-day2-operations",
    [ValidateRange(10, 300)] [int] $SamplingFrequencyInSeconds = 60
)

$ErrorActionPreference = "Stop"
$template = Join-Path $PSScriptRoot "Azure-Local-Day2-DCR.arm.json"

foreach ($command in @("Get-AzContext", "Connect-AzAccount", "Set-AzContext", "Get-AzResourceGroup", "New-AzResourceGroup", "New-AzResourceGroupDeployment")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required Az PowerShell command '$command' was not found. Install the Az.Accounts and Az.Resources modules first."
    }
}

if (-not (Get-AzContext)) {
    Connect-AzAccount
}

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
$context = Get-AzContext
if (-not $context -or $context.Subscription.Id -ne $SubscriptionId) {
    throw "The active Azure subscription does not match -SubscriptionId '$SubscriptionId'."
}

if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
}

$result = New-AzResourceGroupDeployment `
    -Name "azure-local-day2-dcr" `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $template `
    -dcrName $DcrName `
    -location $Location `
    -logAnalyticsWorkspaceResourceId $WorkspaceResourceId `
    -performanceSamplingFrequencyInSeconds $SamplingFrequencyInSeconds

$result.Outputs
Write-Host "DCR deployed. Associate it with every Azure Local Arc-enabled server node using Azure Monitor > Data Collection Rules > Resources." -ForegroundColor Green
Write-Warning "Keep the Microsoft-managed Azure Local Insights DCR enabled. This package is supplemental."
