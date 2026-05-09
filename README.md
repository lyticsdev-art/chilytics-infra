# chilytics-infra

Infrastructure-as-Code + reusable CI/CD + service contracts for the ChiLytics platform.

This is the **fourth** repo in the platform — peer to the three application repos. Owns the deployment surface so the application repos stay clean.

## What lives here

```
chilytics-infra/
├── README.md
├── bicep/
│   ├── main.bicep                 # orchestrator — stitches modules into one env
│   ├── modules/
│   │   ├── app-service.bicep      # Linux container web app (used by backend + inference)
│   │   ├── acr.bicep              # Azure Container Registry (Premium)
│   │   ├── swa.bicep              # Static Web App (frontend)
│   │   ├── key-vault.bicep        # secrets store (HSM-backed)
│   │   ├── storage.bicep          # Blob storage, zone-partitioned per HIPAA rules
│   │   └── app-insights.bicep     # observability per service
│   └── env/
│       ├── prod.bicepparam        # prod params (placeholders — fill in before deploy)
│       └── staging.bicepparam     # staging params
├── workflows/
│   ├── reusable-deploy-app-service.yml  # called by chilytics-inference + chilytics-backend
│   └── reusable-deploy-swa.yml          # called by chilytics-frontend
├── contracts/
│   └── openapi-inference.yaml     # FastAPI contract (single source of truth)
└── docs/
    ├── adr-001-three-repo-split.md
    ├── adr-002-oidc-deploy.md
    └── runbook-onboarding.md      # how to bootstrap a new env from scratch
```

## How the app repos use this

Each app repo's `.github/workflows/deploy.yml` calls the reusable workflows here via `uses:`:

```yaml
# chilytics-backend/.github/workflows/deploy.yml
jobs:
  deploy:
    uses: lyticsdev-art/infra/.github/workflows/reusable-deploy-app-service.yml@main
    with:
      app-name: chilytics-backend
      environment: prod
    secrets: inherit
```

This means: **change the deploy pattern once here, every app picks it up.**

## Bootstrap a new environment

See `docs/runbook-onboarding.md`. TL;DR:

```bash
# 1. Login to Azure with the new tenant
az login --tenant <new-tenant-id>

# 2. Create resource group
az group create -n chilytics-prod -l eastus2

# 3. Deploy main.bicep
az deployment group create \
  -g chilytics-prod \
  -f bicep/main.bicep \
  -p bicep/env/prod.bicepparam

# 4. Federate GitHub OIDC (one-time per env)
# See adr-002-oidc-deploy.md

# 5. Push code from each app repo — workflows take it from there
```

## Compliance ties

Each Bicep module bakes in the requirements from the `ops_hipaa_soc2_external` checklist:
- Customer-managed keys (CMK) on PHI storage
- Private Endpoints on every PaaS service
- TLS 1.2+ enforced via Azure Policy
- Audit log retention ≥ 6 years (HIPAA) → Log Analytics
- Tags: `complianceZone`, `dataResidency`, `owner` required on every resource

The modules are the auditable artifact for HIPAA + SOC 2 evidence. Don't bypass them — extend them.

## License

Proprietary — ChiLytics LLC. All rights reserved.
