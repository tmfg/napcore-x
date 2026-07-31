// User-assigned managed identity, created as its own step so the caller can
// grant it roles (e.g. AcrPull) *before* creating any resource that uses it
// to pull an image - otherwise that resource can start running before the
// role assignment exists/propagates. Deployed at resource group scope.
@description('Azure region.')
param location string

@description('Name of the user-assigned managed identity.')
param name string

param tags object = {}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: name
  location: location
  tags: tags
}

output id string = identity.id
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
