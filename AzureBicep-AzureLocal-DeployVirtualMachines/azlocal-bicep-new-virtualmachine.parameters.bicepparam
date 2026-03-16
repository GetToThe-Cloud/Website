using './azlocal-bicep-new-virtualmachine.bicep'

param name = 'Test-Vm'
param location = 'westeurope'

param securityType = ''
param domainToJoin = 'azurelocalbox.local'
param orgUnitPath = 'OU=Servers,OU=Computers,OU=azurelocalbox,DC=azurelocalbox,DC=local'
param resourceTags = {
  owner: 'Alex ter Neuzen'
  Purpose: 'Azure Local initiative project'
}

param clusterRsg = 'rsg-azl-koogaandezaan-01'
param customLocationName = 'Koog-aan-de-Zaan'
param imageName = '2025-datacenter-azure-edition-02'
param subscriptionId = '' // Subscription ID of the Azure Local environment, can be left empty when deploying from within the Azure Local environment

param logicalNetworkName = 'vnet101'

param keyVault = 'kv-cluster1-01'
param djsecretName = 'domainJoinPassword'
param djaccountName = 'domainJoinAccount'
param laPasswordSecret = 'localAdminPassword'
param laAccountName = 'localAdminAccount'

param processorCores = 4
param memoryInGB = 8
