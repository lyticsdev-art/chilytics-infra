// chilytics-infra — production parameters
// Deploy: az deployment group create -g chilytics-prod -f ../main.bicep -p prod.bicepparam

using '../main.bicep'

param environment = 'prod'
param location = 'eastus2'
param complianceZone = 'phi-us'

// Object IDs (AAD) of users who get Key Vault Administrator
// Get with: az ad user show --id <email> --query id -o tsv
param adminPrincipalIds = [
  '36bd9f0d-93ac-4d90-8c15-78fd63347099'
]
