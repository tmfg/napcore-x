using './main.bicep'

param appName = 'napcorexdemo'
param environmentName = 'dev'
param location = 'swedencentral'
param fileShareQuotaGB = 100

// TODO: error out if the this is unset, instead of silently using a placeholder value.
param buildJobImageTag = 'REPLACE_WITH_BUILD_JOB_IMAGE_TAG'
param osmFileName = 'estonia.pbf'
param gtfsFileName = 'napcorexgtfs.zip'
