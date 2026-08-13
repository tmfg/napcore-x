using './main.bicep'

param appName = 'napcorexdemo'
param environmentName = 'dev'
param location = 'swedencentral'
param fileShareQuotaGB = 100
param osmFileName = 'estonia.pbf'
param gtfsFileName = 'napcorexgtfs.zip'

// buildJobImageTag/serveAppImageTag are intentionally NOT assigned here.
// Set them to correct values in infra/main.local.bicepparam
