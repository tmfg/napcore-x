using './main.bicep'

param appName = 'napcorexdemo'
param environmentName = 'dev'
param location = 'swedencentral'
param fileShareQuotaGB = 100

// Build job disabled TMP
param deployBuildJob = false

// TODO: error out if the this is unset, instead of silently using a placeholder value.
param buildJobImageTag = '2.8.1-f71f0f2'
param osmFileName = 'estonia.pbf'
param gtfsFileName = 'napcorexgtfs.zip'
