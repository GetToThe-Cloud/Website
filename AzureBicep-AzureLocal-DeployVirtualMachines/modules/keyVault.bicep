targetScope = 'resourceGroup'

// ============================================================
// Parameters
// ============================================================

@description('Name of the Key Vault')
param keyVaultName string

@description('Key Vault resource group')
param keyVaultResourceGroup string

@description('Subscription ID where Key Vault exists')
param subscriptionId string

@description('Domain join secret name')
param djSecretName string

@description('Domain join account name secret')
param djAccountName string

@description('Local admin password secret name')
param laPasswordSecret string

@description('Local admin account name secret')
param laAccountName string

// ============================================================
// Existing Resources
// ============================================================

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' existing = {
  name: keyVaultName
  scope: resourceGroup(subscriptionId, keyVaultResourceGroup)
}

resource djSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' existing = {
  parent: keyVault
  name: djSecretName
}

resource djAccount 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' existing = {
  parent: keyVault
  name: djAccountName
}

resource laPassword 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' existing = {
  parent: keyVault
  name: laPasswordSecret
}

resource laAccount 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' existing = {
  parent: keyVault
  name: laAccountName
}

// ============================================================
// Outputs
// ============================================================

@description('Local admin account username')
output localAdminAccount string = laAccount.properties.secretUri

@description('Local admin account password')
@secure()
output localAdminPassword string = laPassword.properties.secretUri

@description('Domain join account username')
output domainJoinAccount string = djAccount.properties.secretUri

@description('Domain join account password')
@secure()
output domainJoinPassword string = djSecret.properties.secretUri
