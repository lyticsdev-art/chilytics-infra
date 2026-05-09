// Static Web App — chilytics-frontend.
// Backed by GitHub Actions deploy via deploymentToken.

@description('SWA name')
param name string

@description('Region — SWA is global but the resource record lives in a region')
param location string

@description('Resource tags')
param tags object

@description('Backend (chilytics-backend) URL — used as a routing hint, NOT a CORS allowlist')
param backendUrl string

resource swa 'Microsoft.Web/staticSites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    repositoryUrl: ''  // populated by GH Actions deploy task
    branch: ''
    buildProperties: {
      appLocation: '/'
      apiLocation: ''
      outputLocation: 'dist'
    }
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

// App settings (made available as env vars at request time, NOT at build)
resource swaConfig 'Microsoft.Web/staticSites/config@2024-04-01' = {
  parent: swa
  name: 'appsettings'
  properties: {
    BACKEND_URL: backendUrl
  }
}

output id string = swa.id
output name string = swa.name
output defaultHostName string = swa.properties.defaultHostname
