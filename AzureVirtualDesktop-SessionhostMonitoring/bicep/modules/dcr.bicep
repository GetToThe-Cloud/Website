metadata description = 'Supplemental Data Collection Rule for AVD Sessionhosts Monitoring 2.0. It does not repeat anything the Microsoft managed microsoft-avdi-<region> rule already collects.'

@description('Name of the Data Collection Rule.')
param dcrName string

@description('Azure region. Must match the region of the session hosts.')
param location string

@description('Resource ID of the Log Analytics workspace that receives the data.')
param workspaceResourceId string

@description('Sampling interval in seconds for the supplemental performance counters.')
@minValue(15)
@maxValue(300)
param samplingFrequencyInSeconds int = 60

@description('Performance counters collected on top of the AVD Insights DCR.')
param counterSpecifiers array = [
  '\\RemoteFX Graphics(*)\\Frames Skipped/Second - Insufficient Server Resources'
  '\\RemoteFX Graphics(*)\\Frames Skipped/Second - Insufficient Network Resources'
  '\\RemoteFX Graphics(*)\\Frames Skipped/Second - Insufficient Client Resources'
  '\\RemoteFX Graphics(*)\\Output Frames/Second'
  '\\Network Interface(*)\\Bytes Total/sec'
  '\\System\\Processor Queue Length'
  '\\Memory\\Committed Bytes'
]

@description('XPath queries for the supplemental Windows event logs.')
param xPathQueries array = [
  'Microsoft-Windows-User Profile Service/Operational!*[System[(Level=1 or Level=2 or Level=3)]]'
]

@description('Tags applied to the Data Collection Rule.')
param tags object = {}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrName
  location: location
  tags: tags
  kind: 'Windows'
  properties: {
    description: 'AVD Sessionhosts Monitoring 2.0 supplemental counters and logs'
    dataSources: {
      performanceCounters: [
        {
          name: 'avdDay2Perf'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: samplingFrequencyInSeconds
          counterSpecifiers: counterSpecifiers
        }
      ]
      windowsEventLogs: [
        {
          name: 'avdDay2Events'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: xPathQueries
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'logAnalyticsWorkspace'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
          'Microsoft-Event'
        ]
        destinations: [
          'logAnalyticsWorkspace'
        ]
      }
    ]
  }
}

@description('Resource ID of the Data Collection Rule.')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Name of the Data Collection Rule.')
output dataCollectionRuleName string = dataCollectionRule.name
