metadata description = 'Optional log search alerts for AVD Sessionhosts Monitoring 2.0: unhealthy session hosts and high P95 input delay.'

@description('Azure region for the alert rules. Use the region of the Log Analytics workspace.')
param location string

@description('Resource ID of the Log Analytics workspace the alerts query.')
param workspaceResourceId string

@description('Resource IDs of the action groups that are notified. Leave empty to create the rules without notifications.')
param actionGroupIds array = []

@description('Threshold in milliseconds for the P95 user input delay alert.')
param inputDelayThresholdMs int = 200

@description('Prefix for the alert rule names.')
param namePrefix string = 'avd-day2'

@description('Tags applied to the alert rules.')
param tags object = {}

var unhealthyQuery = '''
WVDAgentHealthStatus
| where TimeGenerated > ago(15m)
| summarize arg_max(TimeGenerated, Status) by SessionHostName
| where Status != "Available"
'''

var inputDelayQuery = '''
Perf
| where ObjectName == "User Input Delay per Session" and CounterName == "Max Input Delay"
| where InstanceName !in ("Max", "Average")
| summarize P95 = percentile(CounterValue, 95) by Computer
| where P95 > THRESHOLD
'''

resource unhealthySessionHosts 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${namePrefix}-unhealthy-session-hosts'
  location: location
  tags: tags
  properties: {
    displayName: 'AVD - session host not available for 15 minutes'
    description: 'Fires when the AVD agent on a session host reports a status other than Available.'
    severity: 2
    enabled: true
    scopes: [
      workspaceResourceId
    ]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: unhealthyQuery
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: actionGroupIds
    }
  }
}

resource highInputDelay 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${namePrefix}-high-input-delay'
  location: location
  tags: tags
  properties: {
    displayName: 'AVD - P95 input delay above threshold'
    description: 'Fires when the P95 user input delay on a session host stays above the threshold over a 30 minute window.'
    severity: 3
    enabled: true
    scopes: [
      workspaceResourceId
    ]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    criteria: {
      allOf: [
        {
          query: replace(inputDelayQuery, 'THRESHOLD', string(inputDelayThresholdMs))
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: actionGroupIds
    }
  }
}

@description('Resource IDs of the created alert rules.')
output alertRuleIds array = [
  unhealthySessionHosts.id
  highInputDelay.id
]
