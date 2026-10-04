using './security.bicep'

param vaultName = 'kv-clo25-hanita'
param appName = 'app-clo25-hanita'
param deployerObjectId = '0d2cd385-c048-4114-a94f-ea46bd10fa29'

// The secret is read from an environment variable at deploy time.
// The deploy stops with BCP427 if the variable has not been set.
param secretValue = readEnvironmentVariable('SECRET_VALUE')
