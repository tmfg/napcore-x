// Serve app
// Runs otp-serve image on Azure App Service for Containers (Linux). Deployed at resource group scope
//
// The origin is locked down to only accept traffic from Azure Front Door
// (see modules/waf.bicep) via IP access-restriction default-deny plus the
// AzureFrontDoor.Backend service tag AND a X-Azure-FDID header to match
// against this specific Front Door instance

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

@description('Front Door ID (from modules/waf.bicep) used to validate the X-Azure-FDID header and only allow traffic that has actually passed through this specific Front Door instance.')
@minLength(1)
param frontDoorId string

@description('Resource ID of the storage account to send App Service diagnostic logs to.')
param logsStorageAccountId string

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
      ftpsState: 'Disabled'
      // Only Azure Front Door traffic for this specific profile is let
      // through; everything else is denied
      ipSecurityRestrictionsDefaultAction: 'Deny'
      ipSecurityRestrictions: [
        {
          ipAddress: 'AzureFrontDoor.Backend'
          tag: 'ServiceTag'
          action: 'Allow'
          priority: 100
          name: 'AllowThisFrontDoorInstance'
          headers: {
            'x-azure-fdid': [
              frontDoorId
            ]
          }
        }
      ]
      scmIpSecurityRestrictionsDefaultAction: 'Deny'
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

// TODO: Azure Storage Mount gives the app read-write access to
// the whole share (no read-only option). Fix if needed, for example use separate share for the otp graph
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

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-otp-serve-app'
  scope: webApp
  properties: {
    storageAccountId: logsStorageAccountId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
  }
}

output name string = webApp.name
output defaultHostName string = webApp.properties.defaultHostName
