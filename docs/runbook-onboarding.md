# Runbook: bootstrap a new ChiLytics environment

End-to-end steps to provision a new env (prod or staging) on a fresh Azure subscription + MongoDB Atlas account.

**Estimated time:** 90–120 min total. ~30 min of human time + waiting.

## 0. Prerequisites

- Azure subscription (new tenant for ChiLytics Inc — NOT Del's personal)
- MongoDB Atlas org (new, dedicated)
- GitHub org `lyticsdev-art` created
- All 4 repos created: `chilytics-inference`, `chilytics-backend`, `chilytics-frontend`, `chilytics-infra`
- Code pushed to each repo (single squashed initial commit, `main` branch)
- Azure CLI installed locally + `az login --tenant <new-tenant-id>` succeeded
- `gh` CLI installed + authenticated

## 1. Resource group + Bicep deploy

```bash
ENV=prod
RG=chilytics-${ENV}
LOC=eastus2

# Create RG
az group create -n $RG -l $LOC

# Clone infra repo
git clone git@github.com:lyticsdev-art/chilytics-infra.git
cd chilytics-infra

# Update env file with your AAD object ID
EDITOR bicep/env/${ENV}.bicepparam
# Set adminPrincipalIds = ['<your-aad-object-id>']
# Get with: az ad signed-in-user show --query id -o tsv

# Validate + deploy
az deployment group what-if -g $RG -f bicep/main.bicep -p bicep/env/${ENV}.bicepparam
az deployment group create  -g $RG -f bicep/main.bicep -p bicep/env/${ENV}.bicepparam
```

This creates:
- `chilyticsacr${ENV}` — Azure Container Registry (Premium)
- `kv-chilytics-${ENV}` — Key Vault (HSM)
- `chilyticsst${ENV}` — Storage Account (zone-partitioned)
- `chilytics-ai-${ENV}` + workspace — App Insights + Log Analytics
- `chilytics-inference-${ENV}` — App Service (FastAPI container)
- `chilytics-backend-${ENV}` — App Service (Node container)
- `chilytics-frontend-${ENV}` — Static Web App

## 2. OIDC federation

Follow `adr-002-oidc-deploy.md` to:
- Create the federated AAD app registration
- Federate GitHub OIDC for each of the 4 repos
- Set 3 org-level GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`)

## 3. MongoDB Atlas

1. Create org under new ChiLytics-Inc workspace
2. Provision M10+ cluster: `chilytics-${ENV}-cluster`
3. Sign MongoDB BAA (required for HIPAA — M10+ only)
4. Configure CMK referencing Azure Key Vault key
5. Create database user `chilytics-${ENV}-app`, generate password
6. Add Azure Private Endpoint to cluster
7. Store connection string in Key Vault as secret `mongo-connection-string`

## 4. App-level secrets in Key Vault

```bash
KV=kv-chilytics-${ENV}

# LLM keys (rotated, NEW values from new dashboards)
az keyvault secret set --vault-name $KV --name openai-api-key --value "<new-openai-key>"
az keyvault secret set --vault-name $KV --name gemini-api-key --value "<new-gemini-key>"
az keyvault secret set --vault-name $KV --name huggingface-key --value "<new-hf-key>"

# MongoDB
az keyvault secret set --vault-name $KV --name mongo-connection-string --value "mongodb+srv://..."

# JWT + encryption
az keyvault secret set --vault-name $KV --name jwt-secret --value "$(openssl rand -base64 64)"
az keyvault secret set --vault-name $KV --name encryption-key --value "$(openssl rand -base64 24 | head -c 32)"

# Stripe
az keyvault secret set --vault-name $KV --name stripe-secret-key --value "<new-stripe-key>"
az keyvault secret set --vault-name $KV --name stripe-webhook-secret --value "<new-webhook-secret>"
```

## 5. App Service environment configuration

Set Key Vault references in each App Service's appsettings (Bicep does most of this; this step adds the secret references).

```bash
# chilytics-inference
az webapp config appsettings set -g $RG -n chilytics-inference-${ENV} --settings \
  OPENAI_API_KEY="@Microsoft.KeyVault(SecretUri=https://${KV}.vault.azure.net/secrets/openai-api-key/)" \
  GEMINI_API_KEY="@Microsoft.KeyVault(SecretUri=https://${KV}.vault.azure.net/secrets/gemini-api-key/)" \
  MONGO_URI="@Microsoft.KeyVault(SecretUri=https://${KV}.vault.azure.net/secrets/mongo-connection-string/)"

# chilytics-backend (similar pattern — see chilytics-backend/.env.example for full var list)
```

## 6. First deploy

For each app repo, push a tag to trigger the deploy workflow:

```bash
cd chilytics-inference
git tag v0.1.0 && git push origin v0.1.0

cd ../chilytics-backend
git tag v0.1.0 && git push origin v0.1.0

cd ../chilytics-frontend
git tag v0.1.0 && git push origin v0.1.0
```

GitHub Actions will:
1. Build the container (or Vite bundle for frontend)
2. Trivy security scan (HIGH/CRITICAL fails the build)
3. Push to ACR (or upload to SWA)
4. Update App Service / SWA to point at the new image/build
5. Wait for `/health` (or `/healthz`) to return 200
6. Done

## 7. Smoke test

```bash
curl https://chilytics-inference-${ENV}.azurewebsites.net/health
curl https://chilytics-backend-${ENV}.azurewebsites.net/healthz
curl -I https://chilytics-frontend-${ENV}.azurestaticapps.net/   # should 200
```

## 8. Compliance checklist

After deploy, walk through `ops_hipaa_soc2_external.md` and check off:
- [ ] Microsoft BAA signed via Service Trust Portal
- [ ] MongoDB BAA signed
- [ ] CMK enabled on storage + Atlas
- [ ] Private endpoints on every PaaS
- [ ] Audit log retention ≥ 6 years
- [ ] MFA + PIM on admin accounts
- [ ] Quarterly DR drill scheduled

## Recovery

Each step is idempotent — `az deployment group create` with the same params is a no-op. Bicep handles drift. If a step fails, fix and re-run; nothing leaks state.

For app-level rollback: `az webapp config container set --container-image-name <previous-tag>`.
