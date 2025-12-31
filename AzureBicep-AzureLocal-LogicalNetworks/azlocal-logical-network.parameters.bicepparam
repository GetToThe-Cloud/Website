using 'azlocal-logical-network.bicep'

param subscriptionId = '2a234050-17d0-44a2-9755-08e59607bcd9'
//param location = 'westeurope'

param paramsNetworks = [
  {
    parName: 'vnet101'
    parResourceGroupName: 'azl-we-rsg-azl-koogaandezaan-01'
    parLocation: 'westeurope'
    parSubscriptionId: subscriptionId
    parExtendedLocationName: 'koog-aan-de-zaan'
    parVSwitchName: 'ConvergedSwitch(compute_management_storage)'
    parAddressPrefix: '172.16.100.0/24'
    parVlan: 0
    parIpAllocationMethod: 'Static'
    parDnsServers: [
      '172.16.100.9'
    ]
    parDefaultGateway: '172.16.100.1'
    parIpPools: [
      {
        start: '172.16.100.200'
        end: '172.16.100.215'
      }
    ]
    parTags: {}
  }
]
