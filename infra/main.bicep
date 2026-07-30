// Deploy at subscription scope so this template can create the resource group itself:
//   az deployment sub create --location <region> --template-file infra/main.bicep --parameters infra/main.bicepparam

targetScope = 'subscription'

@description('Short name used as a prefix/suffix for resource names. Lowercase letters and numbers only.')
@minLength(3)
@maxLength(15)
param appName string = 'napcorexdemo'

@description('Environment tag, e.g. dev, test, prod. Used in resource group name and tags.')
param environmentName string = 'dev'

@description('Azure region for all resources.')
param location string = 'swedencentral'

@description('Quota (in GiB) for the Azure Files share.')
param fileShareQuotaGB int = 100

var resourceGroupName = 'rg-${appName}-${environmentName}'
// Storage account names must be globally unique, lowercase alphanumeric, 3-24 chars.
var storageAccountName = toLower('st${appName}${environmentName}')
// ACR names must be globally unique, alphanumeric, 5-50 chars.
var acrName = toLower('acr${appName}${environmentName}')

var tags = {
  app: appName
  environment: environmentName
  managedBy: 'bicep'
}

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module acr 'modules/acr.bicep' = {
  name: 'acr-deploy'
  scope: rg
  params: {
    name: acrName
    location: location
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-deploy'
  scope: rg
  params: {
    name: storageAccountName
    location: location
    fileShareQuotaGB: fileShareQuotaGB
    tags: tags
  }
}

output resourceGroupName string = rg.name
output acrName string = acr.outputs.name
output acrLoginServer string = acr.outputs.loginServer
output storageAccountName string = storage.outputs.name
output fileShareName string = storage.outputs.fileShareName
