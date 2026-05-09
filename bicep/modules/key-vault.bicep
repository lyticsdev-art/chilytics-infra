// Key Vault (HSM-backed in prod) — secrets store referenced by App Services.
// Per HIPAA: separate vaults per compliance zone (kv-chilytics-phi-us, etc.).

@description('Vault name (3-24 chars, alphanumeric + hyphens)')
@minLength(3)
@maxLength(24)
param name string

@description('Region')
param location string

@description('Resource tags')
param tags object

@description('SKU — Premium enables HSM-backed keys (required for HIPAA)')
@allowed(['standard', 'premium'])
param sku string = 'premium'

@description('Object IDs (AAD) of admins who get full vault access')
param adminPrincipalIds array = []

@description('Tenant ID — defaults to subscription tenant')
param tenantId string = subscription().tenantId

resource vault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: sku
    }
    tenantId: tenantId
    enableRbacAuthorization: true        // RBAC, not access policies
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'        // restrict via private endpoint in prod
    networkAcls: {
      defaultAction: 'Allow'              // tighten to Deny + private endpoints in prod
      bypass: 'AzureServices'
    }
  }
}

// Grant admins Key Vault Administrator role
resource adminRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in adminPrincipalIds: {
  name: guid(vault.id, principalId, 'KeyVaultAdministrator')
  scope: vault
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')  // Key Vault Administrator
  }
}]

output id string = vault.id
output name string = vault.name
output uri string = vault.properties.vaultUri
