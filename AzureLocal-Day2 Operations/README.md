# Azure Local Day 2 Operations package

This package accompanies the GetToThe.Cloud blog post about building one Azure Monitor Workbook for Azure Local Day 2 Operations.

## Package contents

* `Azure-Local-Day2-DCR.arm.json`: supplemental Data Collection Rule for performance counters not covered by the Azure Local Insights DCR
* `Azure-Local-Day2-Operations.workbook.json`: Azure Monitor Workbook gallery template
* `Deploy-DCR.ps1`: PowerShell deployment helper
* `BLOGPOST.md`: publish-ready English blog post

## Important design note

Enable Azure Local Insights first and keep the Microsoft-managed Insights DCR in place. Microsoft states that the Insights-created DCR contains a special data stream required by Insights. The DCR in this package is supplemental: it intentionally does not collect the SDDC or Health event logs, Processor, Memory Available, Network Interface Bytes Total, or RDMA counters already used by the Insights DCR.

Do not add the same event log or performance counter to both DCRs. Azure Monitor Agent evaluates associated DCRs independently, so overlapping sources can create duplicate records and additional ingestion charges. If the Insights DCR has already been customized with these supplemental counters, remove the overlap before associating this DCR.

## Prerequisites

* A deployed, registered and connected Azure Local system
* Arc-enabled Azure Local nodes
* Azure Monitor Agent available on the nodes
* Azure Local Insights enabled
* A Log Analytics workspace
* Az.Accounts and Az.Resources PowerShell modules
* Permission to deploy DCRs, create the resource group when needed, and create DCR associations

If the modules are not installed yet:

```powershell
Install-Module -Name Az.Accounts, Az.Resources -Scope CurrentUser
```

## Deploy the DCR

```powershell
Connect-AzAccount

./Deploy-DCR.ps1 `
  -ResourceGroupName "rg-monitoring-prod" `
  -SubscriptionId "<subscription-id>" `
  -WorkspaceResourceId "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>" `
  -Location "westeurope"
```

The script deploys the supplemental DCR only; it does not create associations. It verifies and uses the subscription supplied through `-SubscriptionId`. If the resource group does not exist, the script creates it.

After deployment, open the DCR in Azure Monitor and associate it with every Arc-enabled Azure Local server node. Keep the Microsoft-managed Insights DCR associated as well, because it supplies the required Azure Local event logs and baseline counters.

## Import the workbook

1. Open Azure Monitor.
2. Open Workbooks.
3. Create a new workbook.
4. Select Edit.
5. Open Advanced Editor using the `</>` button.
6. Select Gallery Template.
7. Replace the current JSON with the contents of `Azure-Local-Day2-Operations.workbook.json`.
8. Select Apply and save the workbook.
9. Select the Azure Local cluster and Log Analytics workspace parameters.

## Validation queries

Run these queries in the workspace before troubleshooting workbook visuals. The SDDC event query validates the event data supplied by the Microsoft-managed Insights DCR; the supplemental DCR only adds the extra performance counters listed above.

```kusto
Event
| where EventLog =~ "Microsoft-Windows-SDDC-Management/Operational"
| where EventID in (3000, 3002, 3003)
| summarize Records=count(), LastRecord=max(TimeGenerated) by EventID
```

```kusto
Perf
| where ObjectName in~ ("Processor", "Memory", "Network Interface", "Network Adapter", "RDMA Activity")
| summarize Records=count(), LastRecord=max(TimeGenerated) by ObjectName, CounterName
| order by ObjectName asc, CounterName asc
```

```kusto
Heartbeat
| summarize LastHeartbeat=max(TimeGenerated) by Computer
| extend MinutesOld=datetime_diff("minute", now(), LastHeartbeat)
| order by MinutesOld desc
```

## Cost note

Azure Monitor ingestion and retention charges can apply. Overlapping DCR sources can also create duplicate records and additional cost. A 60-second performance sampling interval is a practical starting point, but it is not automatically the right setting for every environment. Measure ingestion, tune counters and retention, and avoid collecting data without an operational use case.

## Known limitations

* Counter names can vary with operating system language, driver implementation and hardware capability.
* RDMA visuals stay empty when RDMA counters are unavailable.
* Perf-based host charts use normalized node names from SDDC event 3000 to scope the selected cluster; a naming mismatch between those events and `Perf.Computer` can leave those charts empty.
* Storage and VM information depends on the shape and availability of Azure Local SDDC management events.
* Balance score thresholds are custom operational guidance, not Microsoft support limits.
* The workbook is a baseline. Test it against your Azure Local release and telemetry before production use.
