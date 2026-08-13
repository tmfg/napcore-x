// Azure Container Registry for otp-build / otp-serve images.
// Deployed at resource group scope

@description('Name of the container registry. Must be globally unique, alphanumeric only.')
param name string

@description('Azure region.')
param location string

param tags object = {}

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    // TODO: public access enabled for now. Make private if needed? But requires private endpoint etc.
    publicNetworkAccess: 'Enabled'
    dataEndpointEnabled: false
    encryption: {
      // customer manager encryption disabled
      status: 'disabled'
    }
    networkRuleBypassAllowedForTasks: false
    // legacy permissions give push/pull to Owner/Contributor but does not allow scoping access by registry
    // switch to 'AbacRepositoryPermissions' to scope access for least privilege
    roleAssignmentMode: 'LegacyRegistryPermissions'
  }
}

output name string = acr.name
output loginServer string = acr.properties.loginServer
output id string = acr.id
