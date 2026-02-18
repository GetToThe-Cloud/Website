using 'azurebicep-azurelandingzone-addvpnconnection.bicep'

// ============================================================================
// Parameters for VPN Connection Deployment
// ============================================================================

var location = 'westeurope'



param tags = {
  Owner: 'Alex ter Neuzen'
  Website: 'https://www.gettothe.cloud'
  Initiative: 'Azure Landing Zone'
  Component: 'VPN Connectivity'
}


param virtualNetworkGatewayName = 'vnet-gw-01'


param localNetworkGateways = [
  {
    name: 'lng-01'
    ipAddress: '' // Replace with actual public IP of remote site
    addressPrefixes: [
      '192.168.1.100.0/24' // Replace with actual remote network ranges
    ]
  }
  {
    name: 'lng-02'
    ipAddress: '' // Replace with actual public IP of remote site
    addressPrefixes: [
      '192.168.2.0/24' // Replace with actual remote network ranges
    ]
  }
]


param vpnConnections = [
  {
    name: 'vnet-gw-01-to-${localNetworkGateways[0].name}-conn'
    sharedKey: 'YOURSHAREDKEY!!!' // Use Azure Key Vault in production
  }
  {
    name: 'vnet-gw-01-to-${localNetworkGateways[1].name}-conn'
    sharedKey: 'YOURSHAREDKEY!!!' // Use Azure Key Vault in production
  }
]
