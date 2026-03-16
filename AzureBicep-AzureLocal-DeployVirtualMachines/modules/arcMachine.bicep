targetScope = 'resourceGroup'

// ============================================================
// Parameters
// ============================================================

@description('Name of the Arc Machine')
param name string

@description('Azure region for the Arc Machine')
param location string

@description('Resource tags')
param resourceTags object

// ============================================================
// Resources
// ============================================================

resource arcMachine 'Microsoft.HybridCompute/machines@2023-06-20-preview' = {
  name: name
  kind: 'HCI'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: resourceTags
}

// ============================================================
// Outputs
// ============================================================

@description('Resource ID of the Arc Machine')
output id string = arcMachine.id

@description('Name of the Arc Machine')
output name string = arcMachine.name
