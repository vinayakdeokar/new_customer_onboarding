#!/bin/bash
set -e

echo "🔐 Getting Azure AD Token for Fabric..."
echo "----- DEBUG IDENTITY -----"
az account show
echo "--------------------------"


ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Failed to get Azure token"
  exit 1
fi


echo "🔐 Fetching SPN secrets from Key Vault..."

SPN_CLIENT_ID=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" \
  --query value -o tsv)

SPN_SECRET=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" \
  --query value -o tsv)

if [ -z "$SPN_CLIENT_ID" ] || [ -z "$SPN_SECRET" ]; then
  echo "❌ Failed to fetch SPN secrets"
  exit 1
fi

echo "🚀 Creating Fabric VNet Databricks Connection..."

HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.fabric.microsoft.com/v1/connections" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"displayName\": \"${CUSTOMER_CODE}\",
    \"gatewayClusterName\": \"vnwt-db-fab-fabric-sub\",
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
  }")

if [ "$HTTP_RESPONSE" -eq 201 ]; then
  echo "✅ Fabric VNet Connection Created Successfully"
else
  echo "❌ Failed to create connection. HTTP Status: $HTTP_RESPONSE"
  cat response.json
  exit 1
fi
