# ADR-002: GitHub OIDC federation for Azure deploys (no long-lived service principals)

**Status:** Accepted
**Date:** 2026-05-01

## Context

Old `deployment.ps1` baked these into source:
- subscription ID `a8d809f7-72d4-4211-a035-9eccda99d026`
- tenant ID `72b76cc8-1d40-4ef6-bfe6-8f6ee73817f2`
- ACR admin credentials via `az acr credential show`
- APIM keys written to `apim-keys.json`

These leak. Even if rotated, old GitHub commits keep them forever.

## Decision

**No service principal secrets in any repo.** Instead, use GitHub OIDC federation:

1. Create a federated AAD app registration per environment (`gh-oidc-prod`, `gh-oidc-staging`).
2. Trust the GitHub OIDC issuer for the org's repos.
3. GitHub Actions exchanges its `id-token` for an Azure access token at runtime — no static secret to leak.

## How it works at runtime

```yaml
permissions:
  id-token: write    # required
  contents: read

steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

Those three "secrets" are **public identifiers**, not secrets — no leakage risk.

## One-time bootstrap (per environment)

```bash
ENV=prod
RG=chilytics-${ENV}
ORG=lyticsdev-art

# 1. Create AAD app registration
APP_ID=$(az ad app create --display-name "gh-oidc-${ENV}" --query appId -o tsv)
az ad sp create --id "$APP_ID"
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

# 2. Federate the GitHub OIDC identity (per repo + per ref)
for repo in chilytics-inference chilytics-backend chilytics-frontend chilytics-infra; do
  for ref_pattern in "ref:refs/heads/main" "environment:${ENV}"; do
    az ad app federated-credential create --id "$APP_ID" --parameters '{
      "name": "gh-'"${repo}"'-'"${ENV}"'-'"$(echo $ref_pattern | tr ':/' '-')"'",
      "issuer": "https://token.actions.githubusercontent.com",
      "subject": "repo:'"${ORG}"'/'"${repo}"':'"${ref_pattern}"'",
      "audiences": ["api://AzureADTokenExchange"]
    }'
  done
done

# 3. Grant the SP Contributor on the resource group
az role assignment create \
  --assignee "$SP_ID" \
  --role Contributor \
  --scope "$(az group show -n "$RG" --query id -o tsv)"

# 4. Grant AcrPush on the registry
ACR_ID=$(az acr show -n chilyticsacr${ENV} --query id -o tsv)
az role assignment create --assignee "$SP_ID" --role AcrPush --scope "$ACR_ID"

# 5. Set GitHub org-level secrets
gh secret set AZURE_CLIENT_ID --org "$ORG" --body "$APP_ID"
gh secret set AZURE_TENANT_ID --org "$ORG" --body "$(az account show --query tenantId -o tsv)"
gh secret set AZURE_SUBSCRIPTION_ID --org "$ORG" --body "$(az account show --query id -o tsv)"
```

## What's still a real secret (must rotate)

OIDC removes Azure SP secrets from the equation, but app-level secrets remain:
- LLM provider keys (OpenAI, Gemini, HuggingFace, NVIDIA)
- MongoDB Atlas connection string
- Stripe webhook secret
- JWT_SECRET, ENCRYPTION_KEY

These live in **Azure Key Vault**, referenced from App Services via Managed Identity (no env-var leakage). Rotate via the standard Key Vault rotation policy (90-day default in `bicep/modules/key-vault.bicep`).

## References

- [GitHub Actions: configure OpenID Connect in Azure](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure: workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
