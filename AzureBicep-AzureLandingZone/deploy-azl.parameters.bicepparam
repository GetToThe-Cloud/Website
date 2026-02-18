using 'deploy-azl.bicep'
@description('Landing Zone Name')

var location = 'westeurope'


param tags = {
  Owner: 'Alex ter Neuzen'
  Department: 'GetToThe.Cloud'
  Purpose: 'Azure Landing Zone for learning and testing purposes'
}

param resourceGroups = [
  {
    name: 'rsg-lz-network-01'
    location: location
    lock: {
      kind: 'CanNotDelete'
      name: 'rsg-lz-network-01-lockdel'
    }
  }
  {
    name: 'rsg-lz-platform-01'
    location: location
    lock: {
      kind: 'CanNotDelete'
      name: 'rsg-lz-platform-01-lockdel'
    }
  }
  {
    name: 'rsg-lz-arc-01'
    location: location
    lock: {
      kind: 'CanNotDelete'
      name: 'rsg-lz-arc-01-lockdel'
    }
  }
  {
    name: 'rsg-lz-privateendpoint-01'
    location: location
    lock: {
      kind: 'CanNotDelete'
      name: 'rsg-lz-privateendpoint-01-lockdel'
    }
  }
  {
    name: 'rsg-lz-privatednszones-01'
    location: location
    lock: {
      kind: 'CanNotDelete'
      name: 'rsg-lz-privatednszones-01-lockdel'
    }
  }
  {
    name: 'rsg-lz-monitoring-01'
    location: location
    lock: {
      kind: 'CanNotDelete'
      name: 'rsg-lz-monitoring-01-lockdel'
    }
  }
]

param logAnalyticsWorkspaces  = [
  {
  name: 'law-lz-01'
  location: location
  resourceGroupName: 'rsg-lz-monitoring-01'
  }
]

param virtualNetworks  = [
  {
    name: 'vnet-c-vpn-01'
    addressPrefixes: [
      '10.190.0.0/16'
    ]
    subnets: [
      {
        name: 'default'
        addressPrefix: '10.190.1.0/24'
      }
      {
        name: 'GatewaySubnet'
        addressPrefix: '10.190.2.0/24'
      }
    ]
    tags: tags
  }
  {
    name: 'vnet-c-01'
    addressPrefixes: [
      '10.200.0.0/16'
    ]
    subnets: [
      {
        name: 'default'
        addressPrefix: '10.200.1.0/24'
      }
      {
        name: 'endpoints'
        addressPrefix: '10.200.2.0/24'
      }

    ]
    tags: tags
  }
  // {
  //   name: 'vnet-c-vms-01'
  //   addressPrefixes: [
  //     '10.201.0.0/16'
  //   ]
  //   subnets: [
  //     {
  //       name: 'default'
  //       addressPrefix: '10.201.1.0/24'
  //     }
  //   ]
  //   tags: tags
  // }
]  

// param vnetPeerings  = [
//   {
//     name: '${prefix}${region}-vnet-c-01-to-${prefix}${region}-vnet-c-vpn-01-peering'
//     remoteVirtualNetworkName: '${prefix}${region}-vnet-c-vpn-01'
//     allowVirtualNetworkAccess: true
//     allowForwardedTraffic: true
//     allowGatewayTransit: false
//     useRemoteGateways: true
//   }
//   {
//     name: '${prefix}${region}-vnet-c-vpn-01-to-${prefix}${region}-vnet-c-01-peering'
//     remoteVirtualNetworkName: '${prefix}${region}-vnet-c-01'
//     allowVirtualNetworkAccess: true
//     allowForwardedTraffic: true
//     allowGatewayTransit: true
//     useRemoteGateways: false
//   }
// ]

param virtualNetworkGateways  = [
  {
    name: 'vnet-gw-01'
    virtualNetworkName: virtualNetworks[0].name
    publicIpAddressName: 'vpnGatewayPublicIP'
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: 'VpnGw1AZ'
    clusterSettings: {}
    //vpnConnections: vpnConnections
  }
]

param localNetworkGateways  = [
  {
    name: 'lng-kadz-01'
    ipAddress: '31.184.98.201'
    addressPrefixes: [
      '172.16.100.0/24'
    ]
  }
]

param vpnConnections  = [
  {
    name: 'vnet-gw-01-to-lng-kadz-01-conn'
    vpnGatewayName: 'vnet-gw-01'
    localNetworkGatewayName: 'lng-kadz-01'
    sharedKey: 'DitiseenSharedKey01!'
  }
  // {
  //   name: 'connection2'
  //   localNetworkGatewayName: localNetworkGateways[1].name
  //   vpnGatewayName: 'vpnGateway'
  //   sharedKey: ''
  // }
]

param publicIpAddresses = [
  {
    Name: 'pip-vgw-c-01'
    Location: location
    ResourceGroupName: 'rsg-lz-network-01'
    Tags: tags
    Sku: 'Standard'
  }
  //   {
  //   Name: 'pip-vgw-c-02'
  //   Location: location
  //   ResourceGroupName: 'rsg-lz-network-01'
  //   Tags: tags
  //   Sku: 'Standard'
  // }
]

param dnsZones = [
  {
    name: 'privatelink.vaultcore.azure.net'
    tags: tags
  }
  {
    name: 'privatelink.file.core.windows.net'
    tags: tags
  }
  {
    name: 'privatelink.blob.core.windows.net'
    tags: tags
  }
  {
    name: 'privatelink.queue.core.windows.net'
    tags: tags
  }
  {
    name: 'privatelink.we.backup.windowsazure.com'
    tags: tags
  }
  {
    name: 'privatelink.wvd.microsoft.com'
    tags: tags
  }
]
