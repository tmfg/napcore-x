// Runs the otp-build image once in Azure Container Instances (ACI), reading
// OSM/GTFS/NeTEx data from the "input/" directory of the Azure Files share and writing
// graph.obj to "output/graph/"  Deployed at resource group scope

@description('Azure region.')
param location string

@description('Resource ID of the user-assigned managed identity to pull the image with. Must already have AcrPull on the registry.')
param identityResourceId string

@description('Login server of the ACR to pull otp-build from, e.g. acrname.azurecr.io.')
param acrLoginServer string

@description('Tag of the otp-build image to run, e.g. 2.8.1-abc1234.')
@minLength(1)
param imageTag string

@description('Storage account name backing the Azure Files share.')
param storageAccountName string

@description('Name of the file share containing the input/ and output/graph/ directories.')
param fileShareName string

@description('Name of the OSM extract file under the share input/osm/ directory.')
param osmFileName string

@description('Name of the GTFS feed file under the share input/transit/ directory.')
param gtfsFileName string

@description('vCPU cores for the build container.')
param cpuCores int = 4

@description('Memory (GiB) for the build container. Must comfortably exceed JAVA_OPTS -Xmx8G.')
param memoryInGB int = 12

param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2025-09-01' = {
  name: 'aci-otp-build'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    osType: 'Linux'
    // Run once and stop - re-deploy this module to run the job again.
    restartPolicy: 'Never'
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        identity: identityResourceId
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
              value: '/mnt/otp-input/input/osm/${osmFileName}'
            }
            {
              name: 'INPUT_GTFS_PATH'
              value: '/mnt/otp-input/input/transit/${gtfsFileName}'
            }
            {
              name: 'OUTPUT_GRAPH_DIR'
              value: '/mnt/otp-output/output/graph'
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
    // Input path mounted as read-only, output as read-write. Actually both are the same file share, so this gives full read-write to input data also. TODO: separate these if needed
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

output containerGroupName string = containerGroup.name
