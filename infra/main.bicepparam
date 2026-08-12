using './main.bicep'

param appName = 'napcorexdemo'
param environmentName = 'dev'
param location = 'swedencentral'
param fileShareQuotaGB = 100

// TODO: error out if the this is unset, instead of silently using a placeholder value.
param buildJobImageTag = '2.8.1-2434f7f-dirty'
param osmFileName = 'estonia.pbf'
param gtfsFileName = 'napcorexgtfs.zip'

param serveAppImageTag = '2.8.1-2434f7f-dirty'
