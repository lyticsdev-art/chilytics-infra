// chilytics-infra — staging parameters
// Deploy: az deployment group create -g chilytics-staging -f ../main.bicep -p staging.bicepparam

using '../main.bicep'

param environment = 'staging'
param location = 'eastus2'
param complianceZone = 'standard'   // staging may use synthetic data; prod is phi-us

param adminPrincipalIds = [
  // '<abdelhak-homi-aad-object-id>'
]
