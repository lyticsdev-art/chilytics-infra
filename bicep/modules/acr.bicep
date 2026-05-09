// Azure Container Registry (Premium) — single registry, geo-replicated optional.
// Used by chilytics-inference + chilytics-backend.

@description('ACR resource name (alphanumeric only, 5-50 chars)')
@minLength(5)
@maxLength(50)
param name string

@description('Region')
param location string

@description('Resource tags')
param tags object

@description('SKU — Premium enables private endpoints + geo-replication')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Premium'

@description('Disable admin user — must use AAD/Managed Identity')
param adminUserEnabled bool = false

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: 'Enabled'  // restrict via private endpoint in prod via networkRuleSet
    zoneRedundancy: sku == 'Premium' ? 'Enabled' : 'Disabled'
    policies: {
      retentionPolicy: {
        days: 30
        status: 'enabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'enabled'
      }
      quarantinePolicy: {
        status: 'enabled'
      }
    }
    encryption: {
      status: 'disabled'  // enable + key vault key in prod
    }
  }
}

output id string = acr.id
output name string = acr.name
output loginServer string = acr.properties.loginServer
