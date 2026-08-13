// Storage account + Azure Files share for OSM/GTFS/NeTEx input and the built OTP graph.
// Deployed at resource group scope

@description('Name of the storage account. Must be globally unique, lowercase alphanumeric, 3-24 chars.')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region.')
param location string

@description('Quota (in GiB) for the file share.')
param fileShareQuotaGB int = 100

param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2025-06-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-06-01' = {
  parent: fileService
  name: 'otp-data'
  properties: {
    shareQuota: fileShareQuotaGB
    // Explicit default access tier for a share in a general-purpose v2 account.
    accessTier: 'TransactionOptimized'
  }
}

// Diagnostic-settings-to-storage-account (waf.bicep, serve-app.bicep) auto-creates blob containers named insights-logs-*
// set retention policy here
resource managementPolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'delete-old-diagnostic-logs'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [
                'blockBlob'
              ]
              prefixMatch: [
                'insights-logs-'
              ]
            }
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 30
                }
              }
            }
          }
        }
      ]
    }
  }
}

output name string = storageAccount.name
output id string = storageAccount.id
output fileShareName string = fileShare.name
