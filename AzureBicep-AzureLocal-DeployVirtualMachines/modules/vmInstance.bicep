targetScope = 'resourceGroup'

// ============================================================
// Parameters
// ============================================================

@description('Name of the VM (computer name)')
param vmName string

@description('Resource name of the Arc Machine')
param arcMachineName string

@description('Custom Location full resource ID')
param customLocationId string

@description('Subscription ID')
param subscriptionId string

@description('Resource group containing the cluster resources')
param clusterResourceGroup string

@description('Name of the marketplace gallery image')
param imageName string

@description('Number of processor cores')
param processorCores int

@description('Memory in GB')
param memoryInGB int

@description('Local admin username')
param localAdminAccount string

@description('Local admin password')
@secure()
param localAdminPassword string

@description('Resource ID of the network interface')
param networkInterfaceId string

@description('Resource ID of the data disk')
param dataDiskId string

// ============================================================
// Existing Resources
// ============================================================

resource arcMachine 'Microsoft.HybridCompute/machines@2023-06-20-preview' existing = {
  name: arcMachineName
}

// ============================================================
// Resources
// ============================================================

resource vmInstance 'Microsoft.AzureStackHCI/virtualMachineInstances@2025-06-01-preview' = {
  name: 'default'
  scope: arcMachine
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    osProfile: {
      adminUsername: localAdminAccount
      adminPassword: localAdminPassword
      computerName: vmName
      windowsConfiguration: {
        provisionVMAgent: true
        provisionVMConfigAgent: true
      }
    }
    hardwareProfile: {
      vmSize: 'Default'
      processors: processorCores
      memoryMB: memoryInGB * 1024
    }
    storageProfile: {
      imageReference: {
        id: '/subscriptions/${subscriptionId}/resourceGroups/${clusterResourceGroup}/providers/Microsoft.AzureStackHCI/marketplaceGalleryImages/${imageName}'
      }
      dataDisks: [
        {
          id: dataDiskId
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaceId
        }
      ]
    }
    httpProxyConfig: {}
  }
}

// ============================================================
// Outputs
// ============================================================

@description('Name of the VM instance')
output name string = vmInstance.name
