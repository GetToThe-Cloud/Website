targetScope = 'resourceGroup'

// ============================================================
// Parameters
// ============================================================

@description('Name of the network interface')
param name string

@description('Azure region')
param location string

@description('Custom Location ID for Azure Stack HCI')
param customLocationId string

@description('Subscription ID')
param subscriptionId string

@description('Resource group containing the logical network')
param logicalNetworkResourceGroup string

@description('Name of the logical network')
param logicalNetworkName string

// ============================================================
// Resources
// ============================================================

resource networkInterface 'Microsoft.AzureStackHCI/networkInterfaces@2025-06-01-preview' = {
  name: name
  location: location
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    ipConfigurations: [
      {
        name: name
        properties: {
          subnet: {
            id: '/subscriptions/${subscriptionId}/resourceGroups/${logicalNetworkResourceGroup}/providers/Microsoft.AzureStackHCI/logicalNetworks/${logicalNetworkName}'
          }
        }
      }
    ]
  }
}

// ============================================================
// Outputs
// ============================================================

@description('Resource ID of the network interface')
output id string = networkInterface.id

@description('Name of the network interface')
output name string = networkInterface.name
