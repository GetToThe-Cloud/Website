targetScope = 'resourceGroup'

// ============================================================
// Parameters
// ============================================================

@description('Name of the virtual hard disk')
param name string

@description('Azure region')
param location string

@description('Custom Location ID for Azure Stack HCI')
param customLocationId string

@description('Size of the data disk in GB')
param diskSizeGB int = 10

@description('Whether the disk is dynamic')
param dynamic bool = true

// ============================================================
// Resources
// ============================================================

resource virtualHardDisk 'Microsoft.AzureStackHCI/virtualHardDisks@2025-06-01-preview' = {
  name: name
  location: location
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    diskSizeGB: diskSizeGB
    dynamic: dynamic
  }
}

// ============================================================
// Outputs
// ============================================================

@description('Resource ID of the virtual hard disk')
output id string = virtualHardDisk.id

@description('Name of the virtual hard disk')
output name string = virtualHardDisk.name
