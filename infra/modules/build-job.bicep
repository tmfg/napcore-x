// Runs the otp-build image once in Azure Container Instances (ACI), reading
// OSM/GTFS from the "input/" directory of the Azure Files share and writing
// graph.obj to "graph/". Deployed at resource group scope (called from main.bicep).
//
// Chose ACI over a Container Apps Job: it's a genuine one-off run (no
// recurring schedule yet), and avoids standing up a Container Apps
// Environment + Log Analytics workspace just for this. Revisit if/when
// scheduling or event triggers are needed.
//
// Pulls from ACR via a user-assigned managed identity (no admin user/shared
// credentials) - the caller must grant that identity AcrPull on the registry,
// see modules/acr-role-assignment.bicep.

@description('Azure region.')
param location string

@description('Login server of the ACR to pull otp-build from, e.g. acrname.azurecr.io.')
param acrLoginServer string

@description('Tag of the otp-build image to run, e.g. 2.8.1-abc1234.')
@minLength(1)
param imageTag string

@description('Storage account name backing the Azure Files share.')
param storageAccountName string

@description('Name of the file share containing the input/ and graph/ directories.')
param fileShareName string

@description('Name of the OSM extract file under the share input/ directory.')
param osmFileName string

@description('Name of the GTFS feed file under the share input/ directory.')
param gtfsFileName string

@description('vCPU cores for the build container.')
param cpuCores int = 4

@description('Memory (GiB) for the build container. Must comfortably exceed JAVA_OPTS -Xmx8G.')
param memoryInGB int = 12

param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-otp-build'
  location: location
  tags: tags
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2025-09-01' = {
  name: 'aci-otp-build'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    osType: 'Linux'
    // Run once and stop - re-deploy this module to run the job again.
    restartPolicy: 'Never'
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        identity: identity.id
      }
    ]
    containers: [
      {
        name: 'otp-build'
        properties: {
          image: '${acrLoginServer}/otp-build:${imageTag}'
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryInGB
            }
          }
          environmentVariables: [
            {
              name: 'INPUT_OSM_PATH'
              value: '/mnt/otp-input/input/${osmFileName}'
            }
            {
              name: 'INPUT_GTFS_PATH'
              value: '/mnt/otp-input/input/${gtfsFileName}'
            }
            {
              name: 'OUTPUT_GRAPH_DIR'
              value: '/mnt/otp-output/graph'
            }
          ]
          volumeMounts: [
            {
              name: 'otp-data-ro'
              mountPath: '/mnt/otp-input'
              readOnly: true
            }
            {
              name: 'otp-data-rw'
              mountPath: '/mnt/otp-output'
              readOnly: false
            }
          ]
        }
      }
    ]
    // The same share is mounted twice (once read-only, once read-write)
    // since ACI's azureFile volume always mounts the whole share, not a
    // subdirectory - this keeps input/ read-only and graph/ writable.
    // TODO: revisit - mounting the same share twice under different
    // permissions is only enforced at the ACI mount level, not by the
    // storage account itself, so a container process could still open the
    // "read-only" mount's underlying share for writes via the read-write
    // mount path. Consider separate file shares (or storage accounts) for
    // input/ vs graph/, or moving input data handling to blob storage with
    // scoped SAS tokens, for real isolation.
    volumes: [
      {
        name: 'otp-data-ro'
        azureFile: {
          shareName: fileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccount.listKeys().keys[0].value
          readOnly: true
        }
      }
      {
        name: 'otp-data-rw'
        azureFile: {
          shareName: fileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccount.listKeys().keys[0].value
          readOnly: false
        }
      }
    ]
  }
}

output identityPrincipalId string = identity.properties.principalId
output containerGroupName string = containerGroup.name
