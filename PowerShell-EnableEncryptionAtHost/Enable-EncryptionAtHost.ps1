<#
.SYNOPSIS
    Zet Encryption at Host aan op bestaande Azure VM's en VM scale sets, in bulk.

.DESCRIPTION
    Draait in twee modi:
      - Report (default): pre-flight check, wijzigt niets. Levert CSV met per
        resource of hij geschikt is, en zo niet: waarom.
      - Apply: stopt de VM, zet securityProfile.encryptionAtHost = true, start
        hem weer. Voor VMSS wordt het instance-profiel bijgewerkt.

    Availability sets en scale sets worden gespreid verwerkt: er wordt nooit
    meer dan een instelbaar aantal leden uit dezelfde set tegelijk stilgelegd.

    Let op: bestaande VM's MOETEN gedeallocate worden. Dit is dus downtime.

.EXAMPLE
    # 1. Eerst alleen rapporteren, inclusief scale sets
    .\Enable-EncryptionAtHost.ps1 -SubscriptionId 'xxxx' -Mode Report -IncludeScaleSets

.EXAMPLE
    # 2. Daarna toepassen op een selectie resource groups
    .\Enable-EncryptionAtHost.ps1 -SubscriptionId 'xxxx' -ResourceGroupName 'rg-app-prd' -Mode Apply

.NOTES
    Vereist: Az.Accounts, Az.Compute
    Feature moet geregistreerd zijn op de subscription (zie Test-Feature hieronder).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    # Optioneel: beperk tot een of meer resource groups. Leeg = hele subscription.
    [string[]]$ResourceGroupName,

    # Optioneel: beperk tot specifieke resource-namen.
    [string[]]$VmName,

    [ValidateSet('Report', 'Apply')]
    [string]$Mode = 'Report',

    # Neem VM scale sets mee in de inventarisatie en verwerking.
    [switch]$IncludeScaleSets,

    # Rol bestaande VMSS-instances mee via een rolling upgrade. Zonder deze
    # switch krijgen alleen nieuwe instances encryption at host.
    [switch]$UpgradeScaleSetInstances,

    # Aantal resources dat tegelijk verwerkt wordt.
    [int]$BatchSize = 5,

    # Max. aantal VM's uit dezelfde availability set / zone dat tegelijk
    # stilgelegd mag worden.
    [int]$MaxConcurrentPerSet = 1,

    # VM's die gestopt waren blijven gestopt na de wijziging.
    [switch]$KeepStoppedVmsStopped,

    [string]$OutputPath = ".\encryption-at-host-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AdeExtensionNames = @('AzureDiskEncryption', 'AzureDiskEncryptionForLinux')

#region Helpers ---------------------------------------------------------------

function Test-Feature {
    <# Controleert of de EncryptionAtHost feature geregistreerd is op de subscription. #>
    $feature = Get-AzProviderFeature -FeatureName 'EncryptionAtHost' `
                                     -ProviderNamespace 'Microsoft.Compute'

    if ($feature.RegistrationState -eq 'Registered') {
        Write-Host "[OK] Feature 'EncryptionAtHost' is geregistreerd." -ForegroundColor Green
        return $true
    }

    Write-Warning @"
Feature 'EncryptionAtHost' staat op status '$($feature.RegistrationState)'.
Registreer hem eerst met:

    Register-AzProviderFeature -FeatureName 'EncryptionAtHost' -ProviderNamespace 'Microsoft.Compute'
    # wacht tot Registered (paar minuten), daarna:
    Register-AzResourceProvider -ProviderNamespace 'Microsoft.Compute'

Registreren alleen wijzigt niets aan bestaande VM's.
"@
    return $false
}

function Get-SupportedSizeLookup {
    <#
        Haalt per locatie op welke VM-sizes EncryptionAtHostSupported = True hebben.
        Gecached per locatie, want Get-AzComputeResourceSku is traag.
    #>
    param([string]$Location)

    if (-not $script:SkuCache) { $script:SkuCache = @{} }
    if ($script:SkuCache.ContainsKey($Location)) { return $script:SkuCache[$Location] }

    Write-Verbose "SKU-capabilities ophalen voor locatie '$Location'..."
    $supported = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    Get-AzComputeResourceSku -Location $Location |
        Where-Object { $_.ResourceType -eq 'virtualMachines' } |
        ForEach-Object {
            $cap = $_.Capabilities | Where-Object Name -eq 'EncryptionAtHostSupported'
            if ($cap -and $cap.Value -eq 'True') { [void]$supported.Add($_.Name) }
        }

    $script:SkuCache[$Location] = $supported
    return $supported
}

function New-ReportRow {
    [ordered]@{
        Kind             = ''
        Name             = ''
        ResourceGroup    = ''
        Location         = ''
        VmSize           = ''
        PowerState       = ''
        SetName          = ''   # availability set, zone of VMSS
        SetType          = ''   # AvailabilitySet | Zone | ScaleSet | None
        OrchestrationMode= ''
        InstanceCount    = ''
        EncryptionAtHost = $false
        SizeSupported    = $false
        HasAde           = $false
        Eligible         = $false
        Reason           = ''
    }
}

function Get-VmEncryptionState {
    <# Bouwt een regel met alle relevante feiten over een standalone VM. #>
    param($Vm)

    $r = New-ReportRow
    $r.Kind          = 'VM'
    $r.Name          = $Vm.Name
    $r.ResourceGroup = $Vm.ResourceGroupName
    $r.Location      = $Vm.Location
    $r.VmSize        = $Vm.HardwareProfile.VmSize

    # Availability set / zone bepalen - bepaalt hoe we later spreiden
    if ($Vm.AvailabilitySetReference -and $Vm.AvailabilitySetReference.Id) {
        $r.SetType = 'AvailabilitySet'
        $r.SetName = ($Vm.AvailabilitySetReference.Id -split '/')[-1]
    }
    elseif ($Vm.Zones -and $Vm.Zones.Count -gt 0) {
        $r.SetType = 'Zone'
        $r.SetName = "$($Vm.Location)-z$($Vm.Zones[0])"
    }
    else {
        $r.SetType = 'None'
        $r.SetName = ''
    }

    if ($Vm.SecurityProfile -and $null -ne $Vm.SecurityProfile.EncryptionAtHost) {
        $r.EncryptionAtHost = [bool]$Vm.SecurityProfile.EncryptionAtHost
    }

    $status = Get-AzVM -ResourceGroupName $Vm.ResourceGroupName -Name $Vm.Name -Status
    $ps = $status.Statuses | Where-Object Code -like 'PowerState/*'
    if ($ps) { $r.PowerState = $ps.Code -replace 'PowerState/', '' }

    # Azure Disk Encryption aanwezig? ADE en encryption at host sluiten elkaar uit.
    $r.HasAde = [bool]($status.Extensions |
        Where-Object { $_.Name -in $AdeExtensionNames -or $_.Type -in $AdeExtensionNames })

    $r.SizeSupported = (Get-SupportedSizeLookup -Location $Vm.Location).Contains($r.VmSize)

    return [pscustomobject](Set-Eligibility -Row $r)
}

function Get-VmssEncryptionState {
    <# Bouwt een regel met alle relevante feiten over een scale set. #>
    param($Vmss)

    $r = New-ReportRow
    $r.Kind              = 'VMSS'
    $r.Name              = $Vmss.Name
    $r.ResourceGroup     = $Vmss.ResourceGroupName
    $r.Location          = $Vmss.Location
    $r.VmSize            = $Vmss.Sku.Name
    $r.SetType           = 'ScaleSet'
    $r.SetName           = $Vmss.Name
    $r.OrchestrationMode = $Vmss.OrchestrationMode
    $r.PowerState        = 'n/a'

    $instances = @(Get-AzVmssVM -ResourceGroupName $Vmss.ResourceGroupName `
                                -VMScaleSetName $Vmss.Name -ErrorAction SilentlyContinue)
    $r.InstanceCount = $instances.Count

    $profile = $Vmss.VirtualMachineProfile
    if ($profile -and $profile.SecurityProfile -and
        $null -ne $profile.SecurityProfile.EncryptionAtHost) {
        $r.EncryptionAtHost = [bool]$profile.SecurityProfile.EncryptionAtHost
    }

    # ADE-extensie in het instance-profiel?
    if ($profile -and $profile.ExtensionProfile -and $profile.ExtensionProfile.Extensions) {
        $r.HasAde = [bool]($profile.ExtensionProfile.Extensions |
            Where-Object { $_.Type -in $AdeExtensionNames -or $_.Name -in $AdeExtensionNames })
    }

    $r.SizeSupported = (Get-SupportedSizeLookup -Location $Vmss.Location).Contains($r.VmSize)

    return [pscustomobject](Set-Eligibility -Row $r)
}

function Set-Eligibility {
    <# Bepaalt of een resource omgezet kan worden en waarom wel/niet. #>
    param($Row)

    $reasons = @()
    if ($Row.EncryptionAtHost)  { $reasons += 'Staat al aan' }
    if ($Row.HasAde)            { $reasons += 'Azure Disk Encryption actief - eerst ontsleutelen' }
    if (-not $Row.SizeSupported){ $reasons += "Size '$($Row.VmSize)' ondersteunt encryption at host niet" }

    $Row.Eligible = ($reasons.Count -eq 0)

    if ($Row.Eligible -and $Row.Kind -eq 'VMSS') {
        $Row.Reason = if ($Row.OrchestrationMode -eq 'Flexible') {
            'Klaar - LET OP: Flexible mode, bestaande instances moeten los omgezet worden'
        }
        else {
            'Klaar - alleen nieuwe instances tenzij je -UpgradeScaleSetInstances gebruikt'
        }
    }
    else {
        $Row.Reason = if ($reasons) { $reasons -join '; ' } else { 'Klaar om aan te zetten' }
    }

    return $Row
}

function Get-SpreadOrder {
    <#
        Herschikt de lijst zodat leden van dezelfde availability set / zone /
        scale set zo ver mogelijk uit elkaar liggen. Voorkomt dat je een hele
        availability set tegelijk deallocate.

        Werkt als round-robin over de groepen: eerst een uit elke set, dan de
        volgende ronde. Met -MaxConcurrentPerSet > 1 pak je er meer per ronde.
    #>
    param(
        [object[]]$Items,
        [int]$PerRound = 1
    )

    $grouped = @{}
    foreach ($item in $Items) {
        $key = if ($item.SetName) { "$($item.SetType):$($item.SetName)" } else { "solo:$($item.Name)" }
        if (-not $grouped.ContainsKey($key)) {
            $grouped[$key] = [System.Collections.Generic.Queue[object]]::new()
        }
        $grouped[$key].Enqueue($item)
    }

    $ordered = [System.Collections.Generic.List[object]]::new()
    while ($grouped.Values.Where({ $_.Count -gt 0 }).Count -gt 0) {
        foreach ($key in @($grouped.Keys)) {
            for ($i = 0; $i -lt $PerRound -and $grouped[$key].Count -gt 0; $i++) {
                $ordered.Add($grouped[$key].Dequeue())
            }
        }
    }

    return $ordered
}

function Enable-EncryptionAtHostOnVm {
    <# Stopt de VM, zet de property, start hem weer. #>
    param($Vm, [bool]$WasRunning)

    $rg   = $Vm.ResourceGroupName
    $name = $Vm.Name

    Write-Host "  -> Deallocaten van $name..." -ForegroundColor DarkGray
    Stop-AzVM -ResourceGroupName $rg -Name $name -Force | Out-Null

    Write-Host "  -> Encryption at host aanzetten op $name..." -ForegroundColor DarkGray
    $fresh = Get-AzVM -ResourceGroupName $rg -Name $name
    Update-AzVM -VM $fresh -ResourceGroupName $rg -EncryptionAtHost $true | Out-Null

    if ($WasRunning -or -not $KeepStoppedVmsStopped) {
        Write-Host "  -> Starten van $name..." -ForegroundColor DarkGray
        Start-AzVM -ResourceGroupName $rg -Name $name | Out-Null
    }

    Write-Host "  [OK] $name" -ForegroundColor Green
}

function Enable-EncryptionAtHostOnVmss {
    <#
        Zet encryption at host op het instance-profiel van de scale set.
        Bestaande instances krijgen het pas na een upgrade/herstart.
    #>
    param($Vmss, $Row)

    $rg   = $Vmss.ResourceGroupName
    $name = $Vmss.Name

    Write-Host "  -> Instance-profiel bijwerken op scale set $name..." -ForegroundColor DarkGray
    $Vmss = Update-AzVmss -ResourceGroupName $rg -VMScaleSetName $name `
                          -VirtualMachineScaleSet $Vmss -EncryptionAtHost $true

    if (-not $UpgradeScaleSetInstances) {
        Write-Warning "  $name bijgewerkt, maar bestaande instances zijn nog niet versleuteld. Gebruik -UpgradeScaleSetInstances."
        return
    }

    if ($Row.OrchestrationMode -eq 'Flexible') {
        Write-Warning "  $name draait in Flexible mode: instances moeten los omgezet of vervangen worden. Overgeslagen."
        return
    }

    $instances = @(Get-AzVmssVM -ResourceGroupName $rg -VMScaleSetName $name)
    Write-Host "  -> $($instances.Count) instance(s) uitrollen, $MaxConcurrentPerSet tegelijk..." -ForegroundColor DarkGray

    for ($i = 0; $i -lt $instances.Count; $i += $MaxConcurrentPerSet) {
        $chunk = $instances[$i..[Math]::Min($i + $MaxConcurrentPerSet - 1, $instances.Count - 1)]
        $ids   = $chunk.InstanceId

        Write-Host "     instances $($ids -join ', ')" -ForegroundColor DarkGray
        Update-AzVmssInstance -ResourceGroupName $rg -VMScaleSetName $name -InstanceId $ids | Out-Null
    }

    Write-Host "  [OK] $name" -ForegroundColor Green
}

#endregion --------------------------------------------------------------------

#region Main ------------------------------------------------------------------

Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Cyan

if (-not (Test-Feature)) {
    throw 'Feature niet geregistreerd. Script gestopt.'
}

# Inventariseren
$vmParams = @{}
if ($ResourceGroupName -and $ResourceGroupName.Count -eq 1) {
    $vmParams['ResourceGroupName'] = $ResourceGroupName[0]
}

$allVms  = @(Get-AzVM @vmParams)
$allVmss = if ($IncludeScaleSets) { @(Get-AzVmss @vmParams) } else { @() }

if ($ResourceGroupName -and $ResourceGroupName.Count -gt 1) {
    $allVms  = $allVms  | Where-Object ResourceGroupName -in $ResourceGroupName
    $allVmss = $allVmss | Where-Object ResourceGroupName -in $ResourceGroupName
}
if ($VmName) {
    $allVms  = $allVms  | Where-Object Name -in $VmName
    $allVmss = $allVmss | Where-Object Name -in $VmName
}

Write-Host "$($allVms.Count) VM('s) en $($allVmss.Count) scale set(s) gevonden. Pre-flight check draaien..." -ForegroundColor Cyan

$report = [System.Collections.Generic.List[object]]::new()
$total  = $allVms.Count + $allVmss.Count
$done   = 0

foreach ($vm in $allVms) {
    $done++
    Write-Progress -Activity 'Pre-flight check' -Status $vm.Name -PercentComplete (($done / [Math]::Max($total,1)) * 100)
    $report.Add((Get-VmEncryptionState -Vm $vm))
}
foreach ($vmss in $allVmss) {
    $done++
    Write-Progress -Activity 'Pre-flight check' -Status $vmss.Name -PercentComplete (($done / [Math]::Max($total,1)) * 100)
    $report.Add((Get-VmssEncryptionState -Vmss $vmss))
}
Write-Progress -Activity 'Pre-flight check' -Completed

$report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Rapport weggeschreven naar: $OutputPath" -ForegroundColor Cyan

# Samenvatting
$report | Group-Object Reason | Sort-Object Count -Descending |
    ForEach-Object { '{0,4}x  {1}' -f $_.Count, $_.Name } | Write-Host

# Overzicht van availability sets: hoeveel leden raak je aan per set?
$setImpact = $report | Where-Object { $_.Eligible -and $_.SetType -eq 'AvailabilitySet' } |
    Group-Object SetName | Sort-Object Count -Descending
if ($setImpact) {
    Write-Host "`nAvailability sets met meerdere leden in scope:" -ForegroundColor Yellow
    $setImpact | Where-Object Count -gt 1 |
        ForEach-Object { '  {0}: {1} VM(s) - wordt gespreid, {2} tegelijk' -f $_.Name, $_.Count, $MaxConcurrentPerSet } |
        Write-Host
}

$eligible = @($report | Where-Object Eligible)
Write-Host "`n$($eligible.Count) resource(s) kunnen aangezet worden." -ForegroundColor Yellow

if ($Mode -eq 'Report') {
    Write-Host "Report-mode: er is niets gewijzigd. Draai opnieuw met -Mode Apply." -ForegroundColor Yellow
    return
}
if ($eligible.Count -eq 0) { return }

# Apply
Write-Warning "Apply-mode: $($eligible.Count) resource(s) worden gewijzigd. VM's worden gestopt en herstart - dit geeft downtime."
if (Read-Host "Typ JA om door te gaan" -ne 'JA') { Write-Host 'Afgebroken.'; return }

$queue     = Get-SpreadOrder -Items $eligible -PerRound $MaxConcurrentPerSet
$succeeded = [System.Collections.Generic.List[string]]::new()
$failed    = [System.Collections.Generic.List[object]]::new()
$counter   = 0

foreach ($item in $queue) {
    $counter++
    $label = '{0}/{1} [{2}]' -f $item.ResourceGroup, $item.Name, $item.Kind
    Write-Host "[$counter/$($queue.Count)] $label" -ForegroundColor White

    try {
        if ($item.Kind -eq 'VMSS') {
            $vmss = Get-AzVmss -ResourceGroupName $item.ResourceGroup -VMScaleSetName $item.Name
            if ($PSCmdlet.ShouldProcess($label, 'Enable encryption at host')) {
                Enable-EncryptionAtHostOnVmss -Vmss $vmss -Row $item
                $succeeded.Add($item.Name)
            }
        }
        else {
            $vm = Get-AzVM -ResourceGroupName $item.ResourceGroup -Name $item.Name
            if ($PSCmdlet.ShouldProcess($label, 'Enable encryption at host')) {
                Enable-EncryptionAtHostOnVm -Vm $vm -WasRunning ($item.PowerState -eq 'running')
                $succeeded.Add($item.Name)
            }
        }
    }
    catch {
        Write-Warning "  [FOUT] $($item.Name): $($_.Exception.Message)"
        $failed.Add([pscustomobject]@{ Name = $item.Name; Kind = $item.Kind; Error = $_.Exception.Message })
    }

    # Adempauze tussen batches, scheelt throttling op de Compute API
    if ($counter % $BatchSize -eq 0 -and $counter -lt $queue.Count) {
        Write-Host "Batch van $BatchSize afgerond. 30 seconden pauze..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 30
    }
}

Write-Host "`nKlaar. Gelukt: $($succeeded.Count) | Mislukt: $($failed.Count)" -ForegroundColor Cyan
if ($failed.Count) { $failed | Format-Table -AutoSize }

#endregion --------------------------------------------------------------------
