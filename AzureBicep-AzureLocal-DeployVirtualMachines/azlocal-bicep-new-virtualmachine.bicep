targetScope = 'resourceGroup'

// ============================================================
// Parameters
// ============================================================

@description('Name of the virtual machine')
param name string

@description('Azure region')
param location string

@description('Security type (optional)')
param securityType string

@description('Domain to join')
param domainToJoin string

@description('Organizational Unit path for domain join')
param orgUnitPath string

@description('Resource tags')
param resourceTags object

@description('Resource group containing Azure Stack HCI cluster resources')
param clusterRsg string

@description('Name of the custom location')
param customLocationName string

@description('Name of the marketplace gallery image')
param imageName string

@description('Subscription ID')
param subscriptionId string

@description('Name of the logical network')
param logicalNetworkName string

@description('Name of the Key Vault')
param keyVault string

@description('Key Vault secret name for domain join password')
param djsecretName string

@description('Key Vault secret name for domain join account')
param djaccountName string

@description('Key Vault secret name for local admin password')
param laPasswordSecret string

@description('Key Vault secret name for local admin account')
param laAccountName string

@description('Number of processor cores')
param processorCores int

@description('Memory in GB')
param memoryInGB int

// ============================================================
// Existing Resources
// ============================================================

resource customLocationId 'Microsoft.ExtendedLocation/customLocations@2021-08-15' existing = {
  name: customLocationName
  scope: resourceGroup(subscriptionId, clusterRsg)
}

resource keyVaultResource 'Microsoft.KeyVault/vaults@2021-06-01-preview' existing = {
  name: keyVault
  scope: resourceGroup(subscriptionId, clusterRsg)
}

// ============================================================
// Variables
// ============================================================

var localAdminAccount = 'vmadmin'
var domainJoinAccount = 'domain_join'

// ============================================================
// Module: Arc Machine
// ============================================================

module arcMachine 'modules/arcMachine.bicep' = {
  name: '${name}-arcmachine'
  params: {
    name: name
    location: location
    resourceTags: resourceTags
  }
}

// ============================================================
// Module: Virtual Hard Disk (Data Disk)
// ============================================================

module dataDisks 'modules/virtualHardDisk.bicep' = {
  name: '${name}-datadisk'
  params: {
    name: '${name}-extradisk'
    location: location
    customLocationId: customLocationId.id
    diskSizeGB: 10
    dynamic: true
  }
}

// ============================================================
// Module: Network Interface
// ============================================================

module networkInterface 'modules/networkInterface.bicep' = {
  name: '${name}-nic'
  params: {
    name: '${name}-nic'
    location: location
    customLocationId: customLocationId.id
    subscriptionId: subscriptionId
    logicalNetworkResourceGroup: clusterRsg
    logicalNetworkName: logicalNetworkName
  }
}

// ============================================================
// Module: Virtual Machine Instance
// ============================================================

module vmInstance 'modules/vmInstance.bicep' = {
  name: '${name}-vminstance'
  params: {
    vmName: name
    arcMachineName: arcMachine.outputs.name
    customLocationId: customLocationId.id
    subscriptionId: subscriptionId
    clusterResourceGroup: clusterRsg
    imageName: imageName
    processorCores: processorCores
    memoryInGB: memoryInGB
    localAdminAccount: localAdminAccount
    localAdminPassword: keyVaultResource.getSecret(laPasswordSecret)
    networkInterfaceId: networkInterface.outputs.id
    dataDiskId: dataDisks.outputs.id
  }
  dependsOn: [
    arcMachine
    networkInterface
    dataDisks
  ]
}

// ============================================================
// Module: Domain Join Extension
// ============================================================

module domainJoin 'modules/domainJoin.bicep' = {
  name: '${name}-domainjoin'
  params: {
    arcMachineName: arcMachine.outputs.name
    location: location
    domainToJoin: domainToJoin
    orgUnitPath: orgUnitPath
    domainJoinAccount: domainJoinAccount
    domainJoinPassword: keyVaultResource.getSecret(djsecretName)
  }
  dependsOn: [
    vmInstance
  ]
}

// ============================================================
// Outputs
// ============================================================

@description('Name of the deployed virtual machine')
output vmName string = name

@description('Arc Machine resource ID')
output arcMachineId string = arcMachine.outputs.id

@description('Network interface resource ID')
output networkInterfaceId string = networkInterface.outputs.id

// Note: Arc Gateway association should be done post-deployment using Azure CLI:
// az arcgateway settings update --resource-group ${arcGwRsg} --subscription ${subscriptionId} --base-provider Microsoft.HybridCompute --base-resource-type machines --base-resource-name ${name} --gateway-resource-id "/subscriptions/${subscriptionId}/resourceGroups/${arcGwRsg}/providers/Microsoft.HybridCompute/gateways/${arcGwName}"
