# AVD Sessionhosts Monitoring 2.0

A free Azure Monitor workbook for Azure Virtual Desktop session hosts, plus the supplemental
Data Collection Rule, the deployment scripts and the KQL behind every chart.

This package belongs to the blog post *Azure Virtual Desktop | Sessionhosts Monitoring 2.0*
on [gettothe.cloud](https://www.gettothe.cloud/), the follow-up to the 2024 session host
monitoring post and the Azure Local Day 2 Operations package.

The Microsoft managed `microsoft-avdi-<region>` Data Collection Rule is never modified.
Everything in this package is additive.

## Contents

| Path | What it is |
| --- | --- |
| `bicep/main.bicep` | Subscription scoped entry point: DCR, associations, optional alerts |
| `bicep/main.bicepparam` | Example parameter file |
| `bicep/modules/dcr.bicep` | The supplemental Data Collection Rule |
| `bicep/modules/dcr-association.bicep` | Association of the DCR with one session host |
| `bicep/modules/alerts.bicep` | Two optional log search alerts |
| `arm/main.json` | ARM template compiled from `main.bicep` |
| `arm/dcr-avd-day2.json` | ARM template compiled from `modules/dcr.bicep` |
| `arm/main.parameters.json` | Parameter file compiled from `main.bicepparam` |
| `workbook/avd-sessionhosts-monitoring-2.0.workbook.json` | The workbook |
| `workbook/build_workbook.py` | Generates the workbook JSON from the queries |
| `scripts/Deploy-AvdDay2Monitoring.ps1` | Deploys the template and optionally the workbook |
| `scripts/Set-AvdHostPoolDiagnostics.ps1` | Enables all diagnostic categories on the host pools |
| `queries/validation-queries.kql` | Run these before you trust the charts |
| `queries/workbook-queries.kql` | The query behind every tab, ready to run standalone |

## Prerequisites

- Azure Virtual Desktop Insights enabled, so the `microsoft-avdi-<region>` DCR exists and the
  Azure Monitor Agent is installed on the session hosts. See
  [Enable Insights to monitor Azure Virtual Desktop](https://learn.microsoft.com/azure/virtual-desktop/insights).
- Host pool diagnostic settings pointing at the same Log Analytics workspace. Use
  `scripts/Set-AvdHostPoolDiagnostics.ps1` if they are not in place yet.
- Permissions: Contributor on the monitoring resource group, Monitoring Contributor on the
  session hosts for the associations, Desktop Virtualization Reader on the host pools and
  Log Analytics Reader on the workspace to read the workbook.
- Tooling: Azure CLI with Bicep, or PowerShell 7 with Az.Accounts, Az.Resources, Az.Compute
  and Az.Monitor.

## Deploy

### Azure CLI

```bash
az deployment sub create \
  --name avd-day2-monitoring \
  --location westeurope \
  --template-file bicep/main.bicep \
  --parameters bicep/main.bicepparam
```

Add `--what-if` first to see what the deployment changes.

### PowerShell

```powershell
./scripts/Deploy-AvdDay2Monitoring.ps1 `
    -SubscriptionId '00000000-0000-0000-0000-000000000000' `
    -MonitoringResourceGroupName 'rg-avd-monitoring' `
    -SessionHostResourceGroupName 'rg-avd-sessionhosts' `
    -Location 'westeurope' `
    -WorkspaceResourceId '/subscriptions/.../workspaces/law-avd-prod-weu' `
    -ImportWorkbook
```

The script collects the session hosts from the resource group, deploys the template and can
import the workbook as a shared workbook. Use `-WhatIf` for a dry run and `-DeployAlerts`
with `-ActionGroupIds` to add the two log search alerts.

### Azure Policy instead of associations

For production, leave `sessionHostNames` empty and let Azure Policy associate the rule, so new
session hosts from your scaling plan or image pipeline are covered automatically. Assign the
built-in policy *Configure Windows Machines to be associated with a Data Collection Rule or a
Data Collection Endpoint* on the resource group with the session hosts, point it at
`dcr-avd-day2-<region>` and create a remediation task. Find the definition with:

```bash
az policy definition list \
  --query "[?contains(displayName, 'Data Collection Rule')].{name:name, displayName:displayName}" \
  --output table
```

The remediation identity needs Monitoring Contributor on the scope you assign the policy to.

## Import the workbook manually

Azure Monitor > Workbooks > New > Advanced Editor (`</>`) > paste
`workbook/avd-sessionhosts-monitoring-2.0.workbook.json` > Apply > Save as a shared workbook in
your monitoring resource group.

Select a workspace, one or more host pools and a time range at the top. If a tab stays empty,
open the Data quality tab first, it will tell you which source is missing.

## What the supplemental DCR collects

At 60 second intervals, on top of what AVD Insights already collects:

- `RemoteFX Graphics(*)\Frames Skipped/Second - Insufficient Server Resources`
- `RemoteFX Graphics(*)\Frames Skipped/Second - Insufficient Network Resources`
- `RemoteFX Graphics(*)\Frames Skipped/Second - Insufficient Client Resources`
- `RemoteFX Graphics(*)\Output Frames/Second`
- `Network Interface(*)\Bytes Total/sec`
- `System\Processor Queue Length`
- `Memory\Committed Bytes`
- `Microsoft-Windows-User Profile Service/Operational`, level Critical, Error and Warning

Change the lists with the `counterSpecifiers` and `xPathQueries` parameters of
`modules/dcr.bicep` rather than editing the template.

## Tabs

| Tab | Answers |
| --- | --- |
| Overview | Which session host needs attention first |
| Session host health | Is a host failing once or flapping all afternoon |
| Capacity & density | What does one session cost on this host |
| User experience | Is it the host, the network or the client |
| Connections & errors | Which host fails connections, and why |
| FSLogix | Are profiles attaching |
| Data quality | Is every source still delivering data |

## Session host names

`Perf.Computer` and `WVDAgentHealthStatus.SessionHostName` do not always use the same format.
Every query normalises both to a lowercase short name with
`tolower(tostring(split(Computer, ".")[0]))`. Query 5 in `validation-queries.kql` shows what the
names look like in your environment.

## Cost

The Perf table is where the cost is. A counter sampled every 30 seconds produces 2,880 records
per instance per host per day, at 60 seconds that is 1,440. Multiply by counters, instances and
hosts. Query 6 in `validation-queries.kql` gives the actual numbers for your workspace. Check
[Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/) for your region.

## Not in scope

This package does not replace AVD Insights, does not monitor the AVD control plane, and does not
know anything about the applications inside a session. The thresholds are starting points. Give
it two weeks of baseline data and adjust them to your environment.

## Regenerating the templates

```bash
bicep build bicep/main.bicep --outfile arm/main.json
bicep build bicep/modules/dcr.bicep --outfile arm/dcr-avd-day2.json
bicep build-params bicep/main.bicepparam --outfile arm/main.parameters.json
python3 workbook/build_workbook.py
```

## License

MIT. Use it, change it, and open a pull request if you improve something.
