// Azure Container Registry for otp-build / otp-serve images.
// Deployed at resource group scope (called from main.bicep).

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
    // Admin user disabled: prefer Azure AD identity (`az acr login`) or
    // managed identity + role assignments (AcrPush/AcrPull) over shared
    // admin credentials.
    adminUserEnabled: false
    // TODO: revisit once build/serve compute (Container Apps/App Service) exists.
    // Disabling public access requires Premium SKU + a private endpoint (VNet),
    // which isn't set up yet. Decided to keep public access for now (2026-07-30).
    publicNetworkAccess: 'Enabled'
    dataEndpointEnabled: false
    encryption: {
      // customer manager encryption disabled
      status: 'disabled'
    }
    networkRuleBypassAllowedForTasks: false
    // TODO: consider switching to 'AbacRepositoryPermissions' later - it
    // stops Owner/Contributor from getting implicit registry-wide push/pull
    // (least-privilege) and allows per-repository scoped role assignments.
    // One-way, registry-wide change - would need any implicit-access
    // tooling/scripts updated to use explicit AcrPush/AcrPull first.
    roleAssignmentMode: 'LegacyRegistryPermissions'
  }
}

output name string = acr.name
output loginServer string = acr.properties.loginServer
output id string = acr.id
