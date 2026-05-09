// App Service (Linux container) — used by chilytics-inference + chilytics-backend.
// Pulls image from ACR via Managed Identity (no admin creds).

@description('Web App name (chilytics-<service>-<env>)')
param name string

@description('Region')
param location string

@description('Resource tags')
param tags object

@description('ACR login server (from acr module)')
param acrLoginServer string

@description('ACR resource ID (for AcrPull role assignment)')
param acrId string

@description('App Insights connection string')
param appInsightsConnectionString string

@description('Key Vault name (for secret references)')
param keyVaultName string

@description('Container image tag — defaults to "latest", set per deploy')
param imageTag string = 'latest'

@description('Health check path on the container')
param healthCheckPath string

@description('Container port')
param containerPort int

@description('Linux App Service Plan SKU')
param appServicePlanSku object = {
  name: 'P1v3'
  tier: 'PremiumV3'
}

// App Service Plan — one plan can host multiple apps; in prod, a single plan
// for both inference + backend keeps cost down. Scale to dedicated plan when
// load profile diverges.
var planName = '${name}-plan'

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  sku: appServicePlanSku
  properties: {
    reserved: true  // Linux
    zoneRedundant: false  // enable in prod when budget allows
  }
  kind: 'linux'
}

resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrLoginServer}/${name}:${imageTag}'
      acrUseManagedIdentityCreds: true
      alwaysOn: true
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      healthCheckPath: healthCheckPath
      appSettings: [
        {
          name: 'WEBSITES_PORT'
          value: string(containerPort)
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'KEY_VAULT_NAME'
          value: keyVaultName
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'DOCKER_ENABLE_CI'
          value: 'true'
        }
      ]
    }
  }
}

// Grant the web app Managed Identity AcrPull on the registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: split(acrId, '/')[8]
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, webApp.id, 'AcrPull')
  scope: acr
  properties: {
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')  // AcrPull
  }
}

// Grant the web app Key Vault Secrets User role
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource kvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, webApp.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')  // Key Vault Secrets User
  }
}

output id string = webApp.id
output name string = webApp.name
output defaultHostName string = webApp.properties.defaultHostName
output principalId string = webApp.identity.principalId
