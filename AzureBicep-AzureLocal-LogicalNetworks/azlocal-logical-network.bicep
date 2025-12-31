// This Bicep template deploys Azure Stack HCI logical networks using the Azure Verified Modules (AVM) pattern.
// It iterates through an array of network configurations to create multiple logical networks with customized settings.
//
// Parameters:
// - subscriptionId: The Azure subscription ID where the resources will be deployed
// - paramsNetworks: An array of network configuration objects, each containing:
//   - parName: The name of the logical network
//   - parResourceGroupName: The resource group containing the custom location
//   - parExtendedLocationName: The name of the custom location (Azure Stack HCI cluster)
//   - parVSwitchName: The name of the virtual switch on the Azure Stack HCI cluster
//   - parAddressPrefix: The IP address prefix in CIDR notation (e.g., 10.0.0.0/24)
//   - parDefaultGateway: The default gateway IP address for the network
//   - parDnsServers: An array of DNS server IP addresses
//   - parIpAllocationMethod: The IP allocation method (e.g., 'Static' or 'Dynamic')
//   - parIpPools: An array of IP pool objects with 'start' and 'end' IP addresses
//   - parTags: Resource tags as key-value pairs
//   - parVlan: The VLAN ID for network segmentation
//
// The module uses the official Azure Verified Module for Azure Stack HCI logical networks (version 0.2.1)
// and configures each network with IP pools, routing, and VLAN settings based on the provided parameters.

param subscriptionId string
param paramsNetworks array

// Loop through each network in the paramsNetworks array to create logical networks
// using the Azure Stack HCI logical network module for Azure Verified Modules.
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
