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

@description('''
TMP solution, perm issue
''')
param deployBuildJob bool = false

@description('Tag of the otp-build image to run for the graph build job, e.g. 2.8.1-abc1234 (see scripts/build-and-push-images.sh).')
@minLength(1)
param buildJobImageTag string

@description('Name of the OSM extract file under the share input/ directory.')
param osmFileName string

@description('Name of the GTFS feed file under the share input/ directory.')
param gtfsFileName string

@description('vCPU cores for the build container.')
param buildJobCpuCores int = 4

@description('Memory (GiB) for the build container.')
param buildJobMemoryInGB int = 12

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

module buildJobIdentity 'modules/identity.bicep' = if (deployBuildJob) {
  name: 'build-job-identity-deploy'
  scope: rg
  params: {
    location: location
    name: 'id-otp-build'
    tags: tags
  }
}

module buildJobAcrAccess 'modules/acr-role-assignment.bicep' = if (deployBuildJob) {
  name: 'build-job-acr-access-deploy'
  scope: rg
  params: {
    acrName: acr.outputs.name
    principalId: buildJobIdentity.?outputs.principalId ?? ''
  }
}

module buildJob 'modules/build-job.bicep' = if (deployBuildJob) {
  name: 'build-job-deploy'
  scope: rg
  params: {
    location: location
    acrLoginServer: acr.outputs.loginServer
    imageTag: buildJobImageTag
    identityResourceId: buildJobIdentity.?outputs.id ?? ''
    storageAccountName: storage.outputs.name
    fileShareName: storage.outputs.fileShareName
    osmFileName: osmFileName
    gtfsFileName: gtfsFileName
    cpuCores: buildJobCpuCores
    memoryInGB: buildJobMemoryInGB
    tags: tags
  }
  // Explicit dependency (no data dependency exists otherwise): the role
  // assignment must exist before the container group is created, since ACI
  // starts pulling the image immediately on creation. Without this, the
  // role assignment module - which only depends on buildJobIdentity, not on
  // buildJob - could be deployed in parallel with or after buildJob,
  // causing "InaccessibleImage" errors.
  dependsOn: [
    buildJobAcrAccess
  ]
}

output resourceGroupName string = rg.name
output acrName string = acr.outputs.name
output acrLoginServer string = acr.outputs.loginServer
output storageAccountName string = storage.outputs.name
output fileShareName string = storage.outputs.fileShareName
output buildJobContainerGroupName string = buildJob.?outputs.containerGroupName ?? ''
