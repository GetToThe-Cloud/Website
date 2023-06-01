@description('Username for the Virtual Machine.')
param vmAdminUserName string
@description('Password for the Virtual Machine.')
@minLength(12)
@secure()
param vmAdminPassword string
@description('Unique DNS Name for the Public IP used to access the Virtual Machine.')
param dnsLabelPrefix string = toLower('${vmName}-${uniqueString(resourceGroup().id, vmName)}')
@description('Name for the Public IP used to access the Virtual Machine.')
param publicIpName string = 'PublicIP-WIN11'
@description('Allocation method for the Public IP used to access the Virtual Machine.')
@allowed([
  'Dynamic'
  'Static'
])
param publicIPAllocationMethod string = 'Dynamic'
@description('SKU for the Public IP used to access the VM.')
@allowed([
  'Basic'
  'Standard'
])
param publicIpSku string = 'Basic'
@description('The Windows version for the VM.')
@allowed([
'2022-datacenter'
'2022-datacenter-azure-edition-core'
'win11-22h2-avd'
])
param OSVersion string = 'win11-22h2-avd'
@description('VM Publisher.')
@allowed([
'microsoftwindowsdesktop'
'MicrosoftWindowsServer'
])
param publisher string = 'microsoftwindowsdesktop'
@description('VM Offer.')
@allowed([
'WindowsServer'
'windows-11'
])
param vmOffer string = 'windows-11'
@description('Size of the virtual machine.')
param vmSize string = 'Standard_B2s'
@description('Location for all resources.')
param location string = resourceGroup().location
@description('Name of the virtual machine.')
param vmName string = 'WIN11'
param addressPrefix string
param subnetName string
param subnetPrefix string
param virtualNetworkName string

var storageAccountName = 'bootdiags${uniqueString(resourceGroup().id)}'
var nicName = 'NIC-WIN11'
var networkSecurityGroupName = 'NSG-WIN11'

resource stg 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
}
resource pip 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: publicIpName
  location: location
  sku: {
    name: publicIpSku
  }
  properties: {
    publicIPAllocationMethod: publicIPAllocationMethod
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}
resource securityGroup 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'default-allow-3389'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}
resource vn 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: securityGroup.id
          }
        }
      }
    ]
  }
}
resource nic 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfigWIN11'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vn.name, subnetName)
          }
        }
      }
    ]
  }
}
resource vm 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUserName
      adminPassword: vmAdminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: publisher
        offer: vmOffer
        sku: OSVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      dataDisks: [
        {
          diskSizeGB: 1023
          lun: 0
          createOption: 'Empty'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: stg.properties.primaryEndpoints.blob
      }
    }
  }
}

output hostname string = pip.properties.dnsSettings.fqdn
