using './main.bicep'

param appName = 'napcorexdemo'
param environmentName = 'dev'
param location = 'swedencentral'
param fileShareQuotaGB = 100

// Placeholder values, committed to git. For real deploys, use
// infra/main.local.bicepparam instead (gitignored - see readme.md).
param buildJobImageTag = 'REPLACE_WITH_BUILD_JOB_IMAGE_TAG'
param serveAppImageTag = 'REPLACE_WITH_SERVE_APP_IMAGE_TAG'
param osmFileName = 'estonia.pbf'
param gtfsFileName = 'napcorexgtfs.zip'
