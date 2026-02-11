#!/bin/bash
set -e

echo "🔐 Getting Azure AD Token for Fabric..."

ACCESS_TOKEN=$(az account get-access-token \
  --resource https://api.fabric.microsoft.com \
  --query accessToken -o tsv)

echo "🚀 Creating Fabric Connection..."

curl -X POST "https://api.fabric.microsoft.com/v1/connections" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"displayName\": \"${CUSTOMER_CODE}\",
    \"connectionDetails\": {
      \"type\": \"AzureDatabricks\",
      \"parameters\": {
        \"serverHostName\": \"${DATABRICKS_HOST}\",
        \"httpPath\": \"${DATABRICKS_SQL_PATH}\",
        \"authenticationType\": \"ServicePrincipal\",
        \"clientId\": \"${SPN_CLIENT_ID}\",
        \"clientSecret\": \"${SPN_SECRET}\",
        \"tenantId\": \"${AZURE_TENANT_ID}\"
      }
    },
    \"privacyLevel\": \"Private\",
    \"allowCreateArtifact\": true
  }"

echo "✅ Fabric Connection Created Successfully"
