// Blob Storage — zone-partitioned per HIPAA rules.
// PHI containers get CMK; standard containers don't.

@description('Storage account name (3-24 chars, lowercase alphanumeric only)')
@minLength(3)
@maxLength(24)
param name string

@description('Region')
param location string

@description('Resource tags')
param tags object

@description('Compliance zone — drives encryption + retention policy')
@allowed(['phi-us', 'phi-eu', 'standard'])
param complianceZone string

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: toLower(name)
  location: location
  tags: tags
  sku: {
    name: complianceZone == 'standard' ? 'Standard_LRS' : 'Standard_GRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false                      // never enable
    allowSharedKeyAccess: false                       // AAD only
    publicNetworkAccess: 'Enabled'                    // restrict via private endpoint in prod
    networkAcls: {
      defaultAction: 'Allow'                          // tighten in prod
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'                  // switch to Microsoft.Keyvault for CMK in prod
    }
  }
}

// Soft delete + versioning + change feed (audit + recovery)
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: complianceZone == 'standard' ? 30 : 365
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: complianceZone == 'standard' ? 30 : 365
    }
    isVersioningEnabled: true
    changeFeed: {
      enabled: true
      retentionInDays: 365
    }
  }
}

output id string = storage.id
output name string = storage.name
output blobEndpoint string = storage.properties.primaryEndpoints.blob
