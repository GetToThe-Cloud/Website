metadata description = 'Associates the Day 2 Data Collection Rule with a single session host virtual machine.'

@description('Name of the session host virtual machine in this resource group.')
param virtualMachineName string

@description('Resource ID of the Data Collection Rule to associate.')
param dataCollectionRuleId string

@description('Name of the association as it appears on the virtual machine.')
param associationName string = 'dcr-avd-day2'

resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: virtualMachineName
}

resource association 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: associationName
  scope: virtualMachine
  properties: {
    description: 'AVD Sessionhosts Monitoring 2.0 supplemental DCR'
    dataCollectionRuleId: dataCollectionRuleId
  }
}

@description('Resource ID of the association.')
output associationId string = association.id
