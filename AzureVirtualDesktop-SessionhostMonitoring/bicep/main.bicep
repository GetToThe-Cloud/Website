metadata description = 'AVD Sessionhosts Monitoring 2.0 - deploys the supplemental Data Collection Rule, associates it with the session hosts and optionally creates the log search alerts.'

targetScope = 'subscription'

@description('Resource group that holds the monitoring resources (Data Collection Rule, alerts).')
param monitoringResourceGroupName string

@description('Resource group that holds the session host virtual machines.')
param sessionHostResourceGroupName string

@description('Azure region for the Data Collection Rule. Must match the region of the session hosts.')
param location string

@description('Resource ID of the Log Analytics workspace used by AVD Insights.')
param workspaceResourceId string

@description('Names of the session host virtual machines to associate with the Data Collection Rule. Leave empty to deploy the rule only.')
param sessionHostNames array = []

@description('Name of the Data Collection Rule. The default follows the dcr-avd-day2-<region> convention used in the blog post.')
param dcrName string = 'dcr-avd-day2-${location}'

@description('Sampling interval in seconds for the supplemental performance counters.')
param samplingFrequencyInSeconds int = 60

@description('Set to true to deploy the two log search alerts.')
param deployAlerts bool = false

@description('Resource IDs of the action groups notified by the alerts.')
param actionGroupIds array = []

@description('Threshold in milliseconds for the P95 user input delay alert.')
param inputDelayThresholdMs int = 200

@description('Tags applied to all deployed resources.')
param tags object = {
  solution: 'avd-sessionhosts-monitoring-2.0'
}

module dataCollectionRule 'modules/dcr.bicep' = {
  name: 'deploy-${dcrName}'
  scope: resourceGroup(monitoringResourceGroupName)
  params: {
    dcrName: dcrName
    location: location
    workspaceResourceId: workspaceResourceId
    samplingFrequencyInSeconds: samplingFrequencyInSeconds
    tags: tags
  }
}

module associations 'modules/dcr-association.bicep' = [
  for sessionHostName in sessionHostNames: {
    name: 'assoc-${uniqueString(sessionHostName)}'
    scope: resourceGroup(sessionHostResourceGroupName)
    params: {
      virtualMachineName: sessionHostName
      dataCollectionRuleId: dataCollectionRule.outputs.dataCollectionRuleId
    }
  }
]

module alerts 'modules/alerts.bicep' = if (deployAlerts) {
  name: 'deploy-avd-day2-alerts'
  scope: resourceGroup(monitoringResourceGroupName)
  params: {
    location: location
    workspaceResourceId: workspaceResourceId
    actionGroupIds: actionGroupIds
    inputDelayThresholdMs: inputDelayThresholdMs
    tags: tags
  }
}

@description('Resource ID of the deployed Data Collection Rule.')
output dataCollectionRuleId string = dataCollectionRule.outputs.dataCollectionRuleId

@description('Number of session hosts associated with the Data Collection Rule.')
output associatedSessionHosts int = length(sessionHostNames)
