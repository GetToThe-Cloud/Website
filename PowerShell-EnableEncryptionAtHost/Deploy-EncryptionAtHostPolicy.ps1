<#
.SYNOPSIS
    Deployt de custom Deny-policy voor encryption at host en wijst de built-in
    audit-policy toe.

.DESCRIPTION
    Twee policies, twee doelen:

      1. Built-in audit  (fc4d8e41-e223-45ea-9bf5-eada37891d87)
         "Virtual machines and virtual machine scale sets should have encryption
         at host enabled". Geeft je een compliance-beeld van de bestaande vloot.

      2. Custom deny/audit (deny-encryption-at-host.json)
         Blokkeert nieuwe VM's en VMSS zonder encryption at host, zodat je niet
         opnieuw drift opbouwt terwijl je de bestaande vloot omzet.

    Er is bewust geen DeployIfNotExists: encryption at host vereist dat de VM
    gedeallocate wordt, en dat kan Azure Policy niet doen. Remediatie loopt via
    Enable-EncryptionAtHost.ps1.

.EXAMPLE
    # Stap 1: alles in audit, meten voor je afdwingt
    .\Deploy-EncryptionAtHostPolicy.ps1 -ManagementGroupId 'mg-landingzones' -Effect Audit

.EXAMPLE
    # Stap 2: pas afdwingen als de vloot om is
    .\Deploy-EncryptionAtHostPolicy.ps1 -ManagementGroupId 'mg-landingzones' -Effect Deny
#>

[CmdletBinding(DefaultParameterSetName = 'ManagementGroup', SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ParameterSetName = 'ManagementGroup')]
    [string]$ManagementGroupId,

    [Parameter(Mandatory, ParameterSetName = 'Subscription')]
    [string]$SubscriptionId,

    [ValidateSet('Audit', 'Deny', 'Disabled')]
    [string]$Effect = 'Audit',

    # Resource groups of resource IDs die buiten de assignment vallen.
    [string[]]$ExcludedScope,

    [string]$DefinitionPath = "$PSScriptRoot\deny-encryption-at-host.json"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BuiltInAuditPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/fc4d8e41-e223-45ea-9bf5-eada37891d87'
$CustomPolicyName     = 'custom-vm-encryption-at-host'

# Scope bepalen
if ($PSCmdlet.ParameterSetName -eq 'ManagementGroup') {
    $scope       = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
    $defScopeArg = @{ ManagementGroupName = $ManagementGroupId }
}
else {
    Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null
    $scope       = "/subscriptions/$SubscriptionId"
    $defScopeArg = @{ SubscriptionId = $SubscriptionId }
}

Write-Host "Scope: $scope" -ForegroundColor Cyan

#region 1. Custom policy definitie -------------------------------------------

if (-not (Test-Path $DefinitionPath)) {
    throw "Policy definitie niet gevonden op '$DefinitionPath'."
}

$definitionJson = Get-Content $DefinitionPath -Raw | ConvertFrom-Json
$props          = $definitionJson.properties

Write-Host "Custom policy definitie '$CustomPolicyName' aanmaken/bijwerken..." -ForegroundColor Cyan

$definition = New-AzPolicyDefinition `
    -Name        $CustomPolicyName `
    -DisplayName $props.displayName `
    -Description $props.description `
    -Policy      ($props.policyRule   | ConvertTo-Json -Depth 30) `
    -Parameter   ($props.parameters   | ConvertTo-Json -Depth 30) `
    -Metadata    ($props.metadata     | ConvertTo-Json -Depth 30) `
    -Mode        $props.mode `
    @defScopeArg

Write-Host "  [OK] $($definition.ResourceId)" -ForegroundColor Green

#endregion

#region 2. Assignments --------------------------------------------------------

# Excluded scopes normaliseren naar resource IDs
$notScopes = @()
foreach ($ex in $ExcludedScope) {
    $notScopes += if ($ex -like '/subscriptions/*') {
        $ex
    }
    else {
        # korte resource group naam -> volledig ID (alleen zinnig bij -SubscriptionId)
        "/subscriptions/$SubscriptionId/resourceGroups/$ex"
    }
}

function New-Assignment {
    param(
        [string]$Name,
        [string]$DisplayName,
        $PolicyDefinitionObject,
        [string]$PolicyDefinitionId,
        [hashtable]$Parameters
    )

    $params = @{
        Name        = $Name
        DisplayName = $DisplayName
        Scope       = $scope
    }
    if ($PolicyDefinitionObject) { $params['PolicyDefinition'] = $PolicyDefinitionObject }
    else { $params['PolicyDefinitionId'] = $PolicyDefinitionId }
    if ($Parameters)  { $params['PolicyParameterObject'] = $Parameters }
    if ($notScopes)   { $params['NotScope'] = $notScopes }

    if ($PSCmdlet.ShouldProcess($Name, 'Create policy assignment')) {
        $a = New-AzPolicyAssignment @params
        Write-Host "  [OK] $DisplayName -> $($a.Name)" -ForegroundColor Green
    }
}

Write-Host "Assignments aanmaken..." -ForegroundColor Cyan

# Built-in audit: altijd Audit, puur voor compliance-zicht
New-Assignment -Name 'audit-encryption-at-host' `
               -DisplayName 'Audit: encryption at host op VMs en VMSS' `
               -PolicyDefinitionId $BuiltInAuditPolicyId

# Custom: effect instelbaar, Deny pas als de vloot om is
New-Assignment -Name 'enforce-encryption-at-host' `
               -DisplayName "Encryption at host verplicht op nieuwe VMs en VMSS ($Effect)" `
               -PolicyDefinitionObject $definition `
               -Parameters @{ effect = $Effect }

#endregion

Write-Host @"

Klaar. Let op:
  - Compliance-resultaten verschijnen na de eerste evaluatiecyclus (tot 30 min).
    Forceren kan met: Start-AzPolicyComplianceScan -ResourceGroupName <rg>
  - Deny werkt alleen op create en update. Bestaande draaiende VM's worden niet
    geraakt tot iemand ze wijzigt - die remedieer je met Enable-EncryptionAtHost.ps1.
  - Controleer de uitgezonderde VM-sizes in de definitie tegen je pre-flight CSV.
"@ -ForegroundColor Yellow
