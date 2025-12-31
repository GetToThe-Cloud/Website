param location string
param subscriptionId string
param paramsImage array

module marketplaceGalleryImage 'br/public:avm/res/azure-stack-hci/marketplace-gallery-image:0.1.0' = [for (imageParam, index) in paramsImage: {
  name: 'img-${imageParam.parImageName}'
  params: {
    // Required parameters
    customLocationResourceId: '/subscriptions/${subscriptionId}/resourcegroups/${imageParam.parResourceGroupName}/providers/microsoft.extendedlocation/customlocations/${imageParam.parExtendedLocationName}'
    identifier: {
      offer: imageParam.parOfferId
      publisher: imageParam.parPublisherId
      sku: imageParam.parSku
    }
    location: location
    name: imageParam.parImageName
    osType: imageParam.parOsType
    version: {
      name: imageParam.parSkuVersion
    }
    hyperVGeneration: imageParam.parHyperVGeneration
    tags: imageParam.parTags
  }
}

]
