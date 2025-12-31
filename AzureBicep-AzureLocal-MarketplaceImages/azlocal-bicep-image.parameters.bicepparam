using './azlocal-bicep-image.bicep'

param subscriptionId = '2a234050-17d0-44a2-9755-08e59607bcd9'
param location = 'westeurope'

param paramsImage = [
  {
    parImageName: 'win11-24h2-avd-m365-01' // e.g. name of the marketplace image as you want to identify it
    parResourceGroupName: '' // e.g. resource group of cluster
    parSubscriptionId: subscriptionId
    parExtendedLocationName: '' // e.g. extended location of cluster
    parOsType: 'Windows' // e.g. 'Windows' or 'Linux'
    parPublisherId: 'microsoftwindowsdesktop' // e.g. 'microsoftwindowsdesktop' for Windows 11 AVD images
    parOfferId: 'office-365' // e.g. 'office-365' for Windows 11 AVD images
    parSku: 'win11-24h2-avd-m365' // e.g. 'win11-24h2-avd-m365' for Windows 11 AVD images
    parSkuVersion: '26100.7462.251209' // e.g. specific version of the image
    parHyperVGeneration: 'V2' // e.g. 'V1' or 'V2'
    parTags: {} // e.g. {
      //   environment: 'demo'
      //   project: 'get-to-the-cloud'
      // }
  }
  {
    parImageName: '2025-datacenter-azure-edition-01'
    parResourceGroupName: ''
    parSubscriptionId: subscriptionId
    parExtendedLocationName: ''
    parOsType: 'Windows'
    parPublisherId: 'microsoftwindowsserver' // e.g. 'microsoftwindowsserver'
    parOfferId: 'windowsserver' // e.g. 'windowsserver'
    parSku: '2025-datacenter-azure-edition' //  e.g. '2025-datacenter-azure-edition'
    parSkuVersion: '26100.7092.251105'
    parHyperVGeneration: 'V2'
    parTags: {}
  }
  {
    parImageName: '2022-datacenter-azure-edition-01'
    parResourceGroupName: ''
    parSubscriptionId: subscriptionId
    parExtendedLocationName: ''
    parOsType: 'Windows'
    parPublisherId: 'microsoftwindowsserver'
    parOfferId: 'windowsserver'
    parSku: '2022-datacenter-azure-edition'
    parSkuVersion: '20348.4405.251112'
    parHyperVGeneration: 'V2'
    parTags: {}
  }
  {
    parImageName: 'win11-25h2-avd-m365-01'
    parResourceGroupName: ''
    parSubscriptionId: subscriptionId
    parExtendedLocationName: ''
    parOsType: 'Windows'
    parPublisherId: 'microsoftwindowsdesktop'
    parOfferId: 'office-365'
    parSku: 'win11-25h2-avd-m365'
    parSkuVersion: '26200.7462.251218'
    parHyperVGeneration: 'V2'
    parTags: {}
  }
]
