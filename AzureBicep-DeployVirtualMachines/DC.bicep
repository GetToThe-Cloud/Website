@description('Username for the Virtual Machine.')
param vmAdminUserName string
@description('Password for the Virtual Machine.')
@minLength(12)
@secure()
param vmAdminPassword string
@description('The Windows version for the VM.')
@allowed([
'2022-datacenter'
'2022-datacenter-azure-edition-core'
'win11-22h2-avd'
])
param OSVersion string = '2022-datacenter'
@description('VM Publisher.')
@allowed([
'microsoftwindowsdesktop'
'MicrosoftWindowsServer'
])
param publisher string = 'MicrosoftWindowsServer'
@description('VM Offer.')
@allowed([
'WindowsServer'
'windows-11'
])
param vmOffer string = 'WindowsServer'
@description('Size of the virtual machine.')
param vmSize string = 'Standard_B2s'
@description('Location for all resources.')
param location string = resourceGroup().location
@description('Name of the virtual machine.')
param vmName string = 'DC01'
param addressPrefix string
param subnetName string
param subnetPrefix string
param virtualNetworkName string


var storageAccountName = 'bootdiags${uniqueString(resourceGroup().id)}'
var nicName = 'NIC-DC01'
var networkSecurityGroupName = 'NSG-DC01'

resource stg 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
}
resource securityGroup 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'default-allow-5985'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '5985'
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
        name: 'ipconfigDC01'
        properties: {
          // privateIPAllocationMethod: 'Dynamic'
          // publicIPAddress: {
          //   id: pip.id
          // }
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
