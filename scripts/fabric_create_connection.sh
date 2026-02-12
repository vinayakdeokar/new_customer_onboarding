#!/bin/bash
set -e

echo "============================================"
echo "🚀 FABRIC CONNECTION AUTOMATION STARTED"
echo "Customer: $CUSTOMER_CODE"
echo "============================================"

GATEWAY_NAME="vnwt-db-fab-fabric-sub"

# --------------------------------------------------
# 1️⃣ Get Power BI Token
# --------------------------------------------------
echo "🔐 Getting Power BI Access Token..."

TOKEN=$(az account get-access-token \
  --resource https://analysis.windows.net/powerbi/api \
  --query accessToken -o tsv)

if [ -z "$TOKEN" ]; then
  echo "❌ Failed to get token"
  exit 1
fi

# --------------------------------------------------
# 2️⃣ Get Customer Credentials from KeyVault
# --------------------------------------------------
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
  echo "❌ SPN credentials not found"
  exit 1
fi

# --------------------------------------------------
# 3️⃣ Get Gateway ID
# --------------------------------------------------
echo "🔍 Fetching Gateway ID..."

GATEWAY_LIST=$(curl -s \
  -H "Authorization: Bearer $TOKEN" \
  https://api.powerbi.com/v1.0/myorg/gateways)

GATEWAY_ID=$(echo "$GATEWAY_LIST" | jq -r \
  --arg NAME "$GATEWAY_NAME" \
  '.value[] | select(.name==$NAME) | .id')

if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
  echo "❌ Gateway not found"
  exit 1
fi

echo "✅ Gateway ID: $GATEWAY_ID"

# --------------------------------------------------
# 4️⃣ Create Connection
# --------------------------------------------------

echo "📡 Creating Fabric Connection..."

cat <<EOF > payload.json
{
  "dataSourceType": "AzureDatabricks",
  "connectionDetails": {
      "server": "$DATABRICKS_HOST",
      "database": "$DATABRICKS_SQL_PATH"
  },
  "credentialDetails": {
      "credentialType": "OAuth2",
      "credentials": {
          "clientId": "$SPN_CLIENT_ID",
          "clientSecret": "$SPN_SECRET",
          "tenantId": "$AZURE_TENANT_ID"
      },
      "privacyLevel": "Private",
      "encryptedConnection": "Encrypted"
  }
}
EOF

HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gateways/$GATEWAY_ID/datasources" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @payload.json)

if [ "$HTTP_RESPONSE" -eq 201 ]; then
  echo "🎉 SUCCESS: Connection Created!"
else
  echo "❌ Failed: $HTTP_RESPONSE"
  cat response.json
  exit 1
fi
