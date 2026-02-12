#!/bin/bash
set -e

echo "============================================"
echo "🚀 FABRIC CONNECTION AUTOMATION STARTED"
echo "Customer: $CUSTOMER_CODE"
echo "============================================"

# -------------------------------------------------
# 1️⃣ Get Fabric Access Token
# -------------------------------------------------
echo "🔐 Getting Fabric Access Token..."

FABRIC_TOKEN=$(az account get-access-token \
  --resource https://api.fabric.microsoft.com \
  --query accessToken -o tsv)

if [ -z "$FABRIC_TOKEN" ]; then
  echo "❌ Failed to get Fabric token"
  exit 1
fi

# -------------------------------------------------
# 2️⃣ Fetch Fabric Gateways
# -------------------------------------------------
echo "🔍 Fetching Fabric Gateways..."

GATEWAYS=$(curl -s \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  https://api.fabric.microsoft.com/v1/gateways)

echo "📄 Gateways Response:"
echo "$GATEWAYS" | jq .

# Auto-detect VirtualNetwork gateway
GATEWAY_ID=$(echo "$GATEWAYS" | jq -r \
  '.value[] | select(.type=="VirtualNetwork") | .id' | head -n 1)

if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
  echo "❌ No VirtualNetwork gateway found"
  exit 1
fi

echo "✅ Using Gateway ID: $GATEWAY_ID"

# -------------------------------------------------
# 3️⃣ Fetch Customer SPN Credentials from KeyVault
# -------------------------------------------------
echo "🔑 Fetching SPN credentials from KeyVault..."

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

# -------------------------------------------------
# 4️⃣ Create Fabric Connection
# -------------------------------------------------
echo "🚀 Creating Fabric Connection..."

PAYLOAD=$(cat <<EOF
{
  "displayName": "${CUSTOMER_CODE}",
  "gatewayClusterId": "${GATEWAY_ID}",
  "connectionDetails": {
    "type": "AzureDatabricks",
    "parameters": {
      "serverHostName": "${DATABRICKS_HOST}",
      "httpPath": "${DATABRICKS_SQL_PATH}",
      "authenticationType": "ServicePrincipal",
      "clientId": "${SPN_CLIENT_ID}",
      "clientSecret": "${SPN_SECRET}",
      "tenantId": "${AZURE_TENANT_ID}"
    }
  },
  "privacyLevel": "Private",
  "allowCreateArtifact": true
}
EOF
)

HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
  -X POST https://api.fabric.microsoft.com/v1/connections \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

echo "📄 API Response:"
cat response.json

if [ "$HTTP_RESPONSE" -eq 201 ]; then
  echo "🎉 SUCCESS: Fabric connection created"
else
  echo "❌ Failed with status $HTTP_RESPONSE"
  exit 1
fi
