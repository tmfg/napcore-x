// Serves graph.obj via the otp-serve image on Azure App Service for
// Containers (Linux). Deployed at resource group scope (called from
// main.bicep).
//
// Pulls from ACR via a user-assigned managed identity (see
// modules/identity.bicep and modules/acr-role-assignment.bicep) - same
// pattern as the build job, no admin credentials.
//
// TODO: the Azure Storage Mount below gives the app read-write access to
// the whole share (App Service's classic storage-mounts feature has no
// read-only option), even though it only needs to read output/graph/.
// Revisit with a separate share/storage account for graph output if
// tighter isolation is needed.

@description('Name of the web app. Must be globally unique (becomes <name>.azurewebsites.net).')
param name string

@description('Name of the App Service Plan.')
param planName string

@description('Azure region.')
param location string

@description('Login server of the ACR to pull otp-serve from, e.g. acrname.azurecr.io.')
param acrLoginServer string

@description('Tag of the otp-serve image to run, e.g. 2.8.1-abc1234.')
@minLength(1)
param imageTag string

@description('Resource ID of the user-assigned managed identity to pull the image with. Must already have AcrPull on the registry.')
param identityResourceId string

@description('Client ID of the same user-assigned managed identity (required for ACR pull via managed identity).')
param identityClientId string

@description('Storage account name backing the Azure Files share.')
param storageAccountName string

@description('Name of the file share containing the output/graph/ directory.')
param fileShareName string

@description('App Service Plan SKU name, e.g. B2.')
param planSkuName string = 'B2'

@description('App Service Plan SKU tier, e.g. Basic.')
param planSkuTier string = 'Basic'

param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource plan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: planSkuName
    tier: planSkuTier
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2025-03-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrLoginServer}/otp-serve:${imageTag}'
      alwaysOn: true
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: identityClientId
      minTlsVersion: '1.2'
      // No FTP deployment is used (image comes from ACR) - disable an
      // otherwise-open, unused attack surface.
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        {
          name: 'OTP_GRAPH_DIR'
          value: '/mnt/otp-data/output/graph'
        }
      ]
    }
  }
}

resource storageMounts 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'azurestorageaccounts'
  properties: {
    'otp-data': {
      type: 'AzureFiles'
      accountName: storageAccountName
      shareName: fileShareName
      mountPath: '/mnt/otp-data'
      accessKey: storageAccount.listKeys().keys[0].value
    }
  }
}

output name string = webApp.name
output defaultHostName string = webApp.properties.defaultHostName
