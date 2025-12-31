//param location string
param subscriptionId string
param paramsNetworks array


module logicalNetworks 'br/public:avm/res/azure-stack-hci/logical-network:0.2.1' = [for (network, index) in paramsNetworks: {
  name: 'ln-${network.parName}'
  params: {
    // Required parameters
    customLocationResourceId: '/subscriptions/${subscriptionId}/resourcegroups/${network.parResourceGroupName}/providers/microsoft.extendedlocation/customlocations/${network.parExtendedLocationName}'
    name: network.parName
    vmSwitchName: network.parVSwitchName
    // Non-required parameters
    addressPrefix: network.parAddressPrefix
    defaultGateway: network.parDefaultGateway
    dnsServers: network.parDnsServers
    ipAllocationMethod: network.parIpAllocationMethod
    ipPools: [
      {
        end: network.parIpPools[0].end
        start: network.parIpPools[0].start
      }
    ]
    routeName: 'default'
    tags: network.parTags
    vlanId: network.parVlan
  }
}]
