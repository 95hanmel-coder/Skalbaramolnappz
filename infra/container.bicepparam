using './container.bicep'

param registryName = 'acrclo25hanita'
param environmentName = 'cae-clo25-hanita'
param containerAppName = 'ca-clo25-hanita'
param containerImage = 'acrclo25hanita.azurecr.io/beacon:v1'
param minReplicas = 1
param maxReplicas = 5
