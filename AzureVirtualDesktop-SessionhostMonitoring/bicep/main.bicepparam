using 'main.bicep'

param monitoringResourceGroupName = 'rg-avd-monitoring'
param sessionHostResourceGroupName = 'rg-avd-sessionhosts'
param location = 'westeurope'
param workspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-avd-prod-weu'

// Leave empty to deploy the Data Collection Rule only, then associate the session
// hosts with Azure Policy. Fill the list to associate them from this deployment.
param sessionHostNames = [
  // 'avd-weu-01'
  // 'avd-weu-02'
]

param samplingFrequencyInSeconds = 60

param deployAlerts = false
param actionGroupIds = []
param inputDelayThresholdMs = 200
