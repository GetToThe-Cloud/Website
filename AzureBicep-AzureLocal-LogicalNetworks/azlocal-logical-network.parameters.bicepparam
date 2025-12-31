using 'azlocal-logical-network.bicep'

param subscriptionId = '' // e.g. '00000000-0000-0000-0000-000000000000'

param paramsNetworks = [
  {
    parName: '' // e.g. 'azlocal-eastus2-01-logical-network-compute'
    parResourceGroupName: '' // e.g. 'azlocal-eastus2-01-rg'
    parLocation: 'westeurope'
    parSubscriptionId: subscriptionId
    parExtendedLocationName: '' // e.g. 'azlocal-eastus2-01'
    parVSwitchName: 'ConvergedSwitch(compute_management_storage)' // e.g. 'ConvergedSwitch(compute_management_storage)'
    parAddressPrefix: '172.16.1.0/24' // e.g. 'your ip range
    parVlan: 0 // e.g. the vlan for this logical network
    parIpAllocationMethod: 'Static'
    parDnsServers: [
      '172.16.1.10' // e.g. 'your dns server ip'
    ]
    parDefaultGateway: '172.16.1.1' // e.g. 'your default gateway ip'
    parIpPools: [ // e.g. 'your ip pool ranges'
      {
        start: '172.16.1.200'
        end: '172.16.1.215'
      }
    ]
    parTags: {} // e.g. {
      //   environment: 'demo'
      //   project: 'get-to-the-cloud'
      // }
  }
]
