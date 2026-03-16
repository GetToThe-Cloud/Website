targetScope = 'resourceGroup'

// ============================================================
// Parameters
// ============================================================

@description('Name of the Arc Machine')
param arcMachineName string

@description('Azure region')
param location string

@description('Domain to join')
param domainToJoin string

@description('Organizational Unit path')
param orgUnitPath string

@description('Domain join account username')
param domainJoinAccount string

@description('Domain join account password')
@secure()
param domainJoinPassword string

// ============================================================
// Existing Resources
// ============================================================

resource arcMachine 'Microsoft.HybridCompute/machines@2023-06-20-preview' existing = {
  name: arcMachineName
}

// ============================================================
// Resources
// ============================================================

resource domainJoinExtension 'Microsoft.HybridCompute/machines/extensions@2023-06-20-preview' = {
  parent: arcMachine
  name: 'joindomain'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      Name: domainToJoin
      OUPath: orgUnitPath
      User: '${domainToJoin}\\${domainJoinAccount}'
      Restart: 'true'
      Options: '3'
    }
    protectedSettings: {
      Password: domainJoinPassword
    }
  }
}

// ============================================================
// Outputs
// ============================================================

@description('Name of the domain join extension')
output name string = domainJoinExtension.name
