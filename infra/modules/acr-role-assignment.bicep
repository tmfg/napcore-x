// Grants a principal (typically a managed identity) a role on an existing
// ACR. Used to give AcrPull to build/serve jobs. Deployed at resource group scope.

@description('Name of the existing ACR to grant access to.')
param acrName string

@description('Object (principal) ID of the identity to grant the role to.')
param principalId string

@description('Built-in role definition GUID (not the full resource ID). Defaults to AcrPull.')
param roleDefinitionId string = '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: acrName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, principalId, roleDefinitionId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
