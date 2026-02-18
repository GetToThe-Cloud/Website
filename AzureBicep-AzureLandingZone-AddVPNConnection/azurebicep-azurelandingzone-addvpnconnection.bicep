// ============================================================================
// Deploy VPN Connections Only
// ============================================================================
// This template deploys only Local Network Gateways and VPN Connections
// Use this for adding new VPN connections to existing VPN Gateway
// ============================================================================

targetScope = 'resourceGroup'

@description('Array of Local Network Gateways to deploy')
param localNetworkGateways array

@description('Array of VPN Connections to deploy')
param vpnConnections array

@description('Name of the existing Virtual Network Gateway')
param virtualNetworkGatewayName string

@description('Tags to apply to resources')
param tags object = {}

@description('Location for resources')
param location string = resourceGroup().location

// ============================================================================
// Get existing VPN Gateway
// ============================================================================

resource existingVpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-11-01' existing = {
  name: virtualNetworkGatewayName
}

// ============================================================================
// Deploy Local Network Gateways
// ============================================================================

module modLocalNetworkGateways 'br/public:avm/res/network/local-network-gateway:0.4.0' = [
  for lng in localNetworkGateways: {
    name: 'lng-deploy-${lng.name}'
    params: {
      name: lng.name
      location: location
      tags: tags
      localGatewayPublicIpAddress: lng.ipAddress
      localNetworkAddressSpace: {
        addressPrefixes: lng.addressPrefixes
      }
    }
  }
]

// ============================================================================
// Deploy VPN Connections
// ============================================================================

module modConnection 'br/public:avm/res/network/connection:0.1.6' = [
  for (connection, i) in vpnConnections: {
    name: 'connection-deploy-${connection.name}'
    dependsOn: [modLocalNetworkGateways]
    params: {
      name: connection.name
      location: location
      tags: tags
      virtualNetworkGateway1: {
        id: existingVpnGateway.id
      }
      localNetworkGateway2ResourceId: modLocalNetworkGateways[i].outputs.resourceId
      connectionType: 'IPsec'
      vpnSharedKey: connection.sharedKey
      enableBgp: false
    }
  }
]

// ============================================================================
// Outputs
// ============================================================================

@description('Array of Local Network Gateway resource IDs')
output localNetworkGatewayResourceIds array = [for (lng, i) in localNetworkGateways: modLocalNetworkGateways[i].outputs.resourceId]

@description('Array of Local Network Gateway names')
output localNetworkGatewayNames array = [for (lng, i) in localNetworkGateways: modLocalNetworkGateways[i].outputs.name]

@description('Array of VPN Connection resource IDs')
output connectionResourceIds array = [for (connection, i) in vpnConnections: modConnection[i].outputs.resourceId]

@description('Array of VPN Connection names')
output connectionNames array = [for (connection, i) in vpnConnections: modConnection[i].outputs.name]

@description('VPN Gateway resource ID used for connections')
output vpnGatewayResourceId string = existingVpnGateway.id

@description('VPN Gateway name used for connections')
output vpnGatewayName string = existingVpnGateway.name
