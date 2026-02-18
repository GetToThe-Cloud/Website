targetScope = 'subscription'

param virtualNetworks array
param resourceGroups array
param tags object
//param vnetPeerings array
param virtualNetworkGateways array
param localNetworkGateways array
param logAnalyticsWorkspaces array
param publicIpAddresses array
param dnsZones array
param vpnConnections array

var prefix = 'azl'
var region = 'we'

// ============================================================================
// Deploy Resource Groups
// ============================================================================

module resourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = [
  for rg in resourceGroups: {
    name: 'rg-deploy-${rg.Name}'
    params: {
      name: rg.Name
      location: rg.Location
      lock: rg.Lock
      tags: tags
    }
  }
]

resource resRsgMonitoring 'Microsoft.Resources/resourceGroups@2025-04-01' existing = {
  dependsOn: [resourceGroup]
  name: '${prefix}-${region}-rsg-lz-monitoring-01'
}
resource resRsgNetwork 'Microsoft.Resources/resourceGroups@2025-04-01' existing = {
  dependsOn: [resourceGroup]
  name: '${prefix}-${region}-rsg-lz-network-01'
}
resource resRsgDnszones 'Microsoft.Resources/resourceGroups@2025-04-01' existing = {
  dependsOn: [resourceGroup]
  name: '${prefix}-${region}-rsg-lz-privatednszones-01'
}

module modLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.15.0' = [
  for law in logAnalyticsWorkspaces: {
    name: 'law-deploy-${law.name}'
    dependsOn: [resourceGroup]
    params: {
      name: law.name
      location: law.location
    }
    scope: resRsgMonitoring
  }
]

module modVirtualNetworks 'br/public:avm/res/network/virtual-network:0.7.2' = [
  for vnet in virtualNetworks: {
    name: 'vnet-deploy-${vnet.name}'
    dependsOn: [resourceGroup, modLogAnalyticsWorkspace]
    scope: resRsgNetwork
    params: {
      name: vnet.name
      addressPrefixes: vnet.addressPrefixes
      subnets: [
        for subnet in vnet.subnets: {
          name: subnet.name
          addressPrefix: subnet.addressPrefix
        }
      ]
      tags: vnet.tags
      diagnosticSettings: [
        {
          metricCategories: [
            {
              category: 'AllMetrics'
            }
          ]
          name: 'customSetting'
          workspaceResourceId: modLogAnalyticsWorkspace[0].outputs.resourceId
        }
      ]
    }
  }
]

module modpublicIpAddresses 'br/public:avm/res/network/public-ip-address:0.5.1' = [for pip in publicIpAddresses: {
  name: 'public-ip-deploy-${pip.name}'
  scope: resRsgNetwork
  params: {
    name: pip.Name
    location: pip.Location
    publicIPAllocationMethod: 'Static'
    skuName: pip.Sku
    tags: pip.tags
  }
}]  

module modVirtualNetworkGateways 'br/public:avm/res/network/virtual-network-gateway:0.10.1' = [
  for vnetGw in virtualNetworkGateways: {
    name: 'vnet-gw-deploy-${vnetGw.name}'
    dependsOn: [modVirtualNetworks,modpublicIpAddresses]
    scope: resRsgNetwork
    params: {
      name: vnetGw.name
      gatewayType: vnetGw.gatewayType
      vpnType: vnetGw.vpnType
      skuName: vnetGw.sku
      existingPrimaryPublicIPResourceId: modpublicIpAddresses[0].outputs.resourceId
      virtualNetworkResourceId: modVirtualNetworks[0].outputs.resourceId
      clusterSettings: {
        clusterMode: 'activePassiveNoBgp'
      }
    }
  }
]

module modConnection 'br/public:avm/res/network/connection:0.1.6' = [
  for (connection, i) in vpnConnections: {
    scope: resRsgNetwork
    name: 'connection-deploy-${connection.name}'
    dependsOn: [modVirtualNetworkGateways, modLocalNetworkGateways]
    params: {
      name: connection.name
      virtualNetworkGateway1: {
        id: modVirtualNetworkGateways[0].outputs.resourceId
      }
      localNetworkGateway2ResourceId: modLocalNetworkGateways[0].outputs.resourceId
      connectionType: 'IPsec'
      vpnSharedKey: connection.sharedKey
    }
  }
]

module modDnsZones 'br/public:avm/res/network/private-dns-zone:0.5.0' = [
  for dnsZone in dnsZones: {
    name: 'dnszone-deploy-${dnsZone.name}'
    scope: resRsgDnszones
    params: {
      name: dnsZone.name
      tags: dnsZone.tags
    }
  }
]

module modLocalNetworkGateways 'br/public:avm/res/network/local-network-gateway:0.4.0' = [
  for lng in localNetworkGateways: {
    name: 'lng-deploy-${lng.name}'
    dependsOn: [modVirtualNetworkGateways]
    scope: resRsgNetwork
    params: {
      name: lng.name
      localGatewayPublicIpAddress: lng.ipAddress
      localNetworkAddressSpace: {
        addressPrefixes: lng.addressPrefixes
      }
    }
  }
]
