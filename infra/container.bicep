// Infrastructure for the container track: registry, Container Apps
// environment, and the container app.

@description('Region. Defaults to resource group location. Shared below.')
param location string = resourceGroup().location

@description('Registry name. Lowercase letters and digits only, 5-50 characters.')
@minLength(5)
@maxLength(50)
param registryName string

@description('Registry pricing tier. Basic is plenty for this course.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param registrySku string = 'Basic'

@description('Name of the Container Apps environment.')
param environmentName string

@description('Name of the container app. Becomes part of the URL.')
param containerAppName string

@description('Full image reference, for example myregistry.azurecr.io/beacon:v1.')
param containerImage string

@description('Port the app listens on inside the container. .NET 10: 8080.')
param targetPort int = 8080

@description('Minimum replicas. 0 = scale to zero, at the cost of a cold start.')
@minValue(0)
@maxValue(5)
param minReplicas int = 1

@description('Maximum number of replicas the app may scale out to.')
@minValue(1)
@maxValue(10)
param maxReplicas int = 5

@description('Concurrent requests per replica before another one starts.')
param concurrentRequests int = 20

@description('CPU cores per replica. Must match the memory below.')
@allowed([
  '0.25'
  '0.5'
  '0.75'
  '1.0'
])
param containerCpu string = '0.5'

@description('Memory per replica. Must match the CPU value per the table above.')
@allowed([
  '0.5Gi'
  '1.0Gi'
  '1.5Gi'
  '2.0Gi'
])
param containerMemory string = '1.0Gi'

var registryPasswordSecretName = 'acr-password'
var appFqdn = app.properties.configuration.ingress.fqdn

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: registryName
  location: location
  sku: {
    name: registrySku
  }
  properties: {
    adminUserEnabled: true
  }
}

resource environment 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: environmentName
  location: location
  properties: {}
}

resource app 'Microsoft.App/containerApps@2026-01-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: {
        external: true
        targetPort: targetPort
        allowInsecure: false
        transport: 'auto'
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: registryPasswordSecretName
        }
      ]
      secrets: [
        {
          name: registryPasswordSecretName
          value: acr.listCredentials().passwords[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'app'
          image: containerImage
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '${concurrentRequests}'
              }
            }
          }
        ]
      }
    }
  }
}

output loginServer string = acr.properties.loginServer
output appUrl string = 'https://${appFqdn}'
output healthUrl string = 'https://${appFqdn}/health'
