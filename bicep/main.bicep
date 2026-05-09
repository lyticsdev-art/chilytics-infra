// chilytics-infra — main orchestrator
// Stitches modules into one environment.
// Deploy: az deployment group create -g <rg> -f main.bicep -p env/<env>.bicepparam

targetScope = 'resourceGroup'

// ── Parameters ─────────────────────────────────────────────
@description('Environment name: prod, staging, or dev')
@allowed(['prod', 'staging', 'dev'])
param environment string

@description('Azure region for primary resources')
param location string = resourceGroup().location

@description('Compliance zone tag — drives data residency + retention')
@allowed(['phi-us', 'phi-eu', 'standard'])
param complianceZone string = 'standard'

@description('Object IDs of admins who get full Key Vault access')
param adminPrincipalIds array = []

// ── Naming convention ──────────────────────────────────────
// chilytics-<service>-<env>  for resources that allow hyphens
// chilytics<service><env>    for resources that don't (storage, ACR)
var prefix = 'chilytics'
var envSuffix = environment

// Common tags applied to every resource
var commonTags = {
  project: 'chilytics'
  environment: environment
  complianceZone: complianceZone
  managedBy: 'chilytics-infra'
}

// ── Modules ────────────────────────────────────────────────

module acr 'modules/acr.bicep' = {
  name: 'acr-deployment'
  params: {
    name: '${prefix}acr${envSuffix}'
    location: location
    tags: commonTags
  }
}

module appInsights 'modules/app-insights.bicep' = {
  name: 'appinsights-deployment'
  params: {
    name: '${prefix}-ai-${envSuffix}'
    location: location
    tags: commonTags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    name: 'kv-${prefix}-${envSuffix}'
    location: location
    tags: commonTags
    adminPrincipalIds: adminPrincipalIds
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    name: '${prefix}st${envSuffix}'
    location: location
    tags: commonTags
    complianceZone: complianceZone
  }
}

module inferenceApp 'modules/app-service.bicep' = {
  name: 'inference-app-deployment'
  params: {
    name: '${prefix}-inference-${envSuffix}'
    location: location
    tags: union(commonTags, { service: 'chilytics-inference' })
    acrLoginServer: acr.outputs.loginServer
    acrId: acr.outputs.id
    appInsightsConnectionString: appInsights.outputs.connectionString
    keyVaultName: keyVault.outputs.name
    healthCheckPath: '/health'
    containerPort: 8000
  }
}

module backendApp 'modules/app-service.bicep' = {
  name: 'backend-app-deployment'
  params: {
    name: '${prefix}-backend-${envSuffix}'
    location: location
    tags: union(commonTags, { service: 'chilytics-backend' })
    acrLoginServer: acr.outputs.loginServer
    acrId: acr.outputs.id
    appInsightsConnectionString: appInsights.outputs.connectionString
    keyVaultName: keyVault.outputs.name
    healthCheckPath: '/healthz'
    containerPort: 5000
  }
}

module frontendSwa 'modules/swa.bicep' = {
  name: 'frontend-swa-deployment'
  params: {
    name: '${prefix}-frontend-${envSuffix}'
    location: location
    tags: union(commonTags, { service: 'chilytics-frontend' })
    backendUrl: 'https://${backendApp.outputs.defaultHostName}'
  }
}

// ── Outputs ────────────────────────────────────────────────
output acrLoginServer string = acr.outputs.loginServer
output keyVaultUri string = keyVault.outputs.uri
output inferenceAppUrl string = 'https://${inferenceApp.outputs.defaultHostName}'
output backendAppUrl string = 'https://${backendApp.outputs.defaultHostName}'
output frontendSwaUrl string = 'https://${frontendSwa.outputs.defaultHostName}'
output appInsightsConnectionString string = appInsights.outputs.connectionString
