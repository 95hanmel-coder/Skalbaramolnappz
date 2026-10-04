// Infrastructure for the web app track: App Service plan + web app.
// Deployed into an existing resource group with az deployment group create.

@description('Region. Defaults to the location of the resource group.')
param location string = resourceGroup().location

@description('Name of the web app. Part of the URL, must be globally unique.')
param appName string

@description('Name of the App Service plan. It already exists, so pass its name.')
param planName string

@description('Plan size. B1 = Basic, P0v3 = Premium v3.')
@allowed([
  'B1'
  'P0v3'
])
param skuName string = 'B1'

@description('Number of instances to run. B1 allows a maximum of 3.')
@minValue(1)
@maxValue(3)
param instanceCount int = 2

var runtimeStack = 'DOTNETCORE|10.0'
var healthCheckPath = '/health'

resource plan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: skuName
    capacity: instanceCount
  }
  properties: {
    reserved: true
  }
}

resource app 'Microsoft.Web/sites@2025-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: runtimeStack
      healthCheckPath: healthCheckPath
      minTlsVersion: '1.3'
      alwaysOn: true
    }
  }
}

var hostName = app.properties.defaultHostName

output appUrl string = 'https://${hostName}'
output healthUrl string = 'https://${hostName}${healthCheckPath}'
