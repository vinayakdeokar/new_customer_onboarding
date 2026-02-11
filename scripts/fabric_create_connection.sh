#!/bin/bash
set -e

GATEWAY_NAME="vnwt-db-fab-fabric-sub"

echo "🔐 Getting Manager Token..."
MANAGER_ACCESS_TOKEN=$(az account get-access-token \
  --resource https://analysis.windows.net/powerbi/api \
  --query accessToken -o tsv)

if [ -z "$MANAGER_ACCESS_TOKEN" ]; then
  echo "❌ Failed to get Manager token"
  exit 1
fi

echo "🔍 Listing Fabric Connections..."

FABRIC_TOKEN=$(az account get-access-token \
  --resource https://analysis.windows.net/powerbi/api \
  --query accessToken -o tsv)

curl -s -X GET \
  "https://api.fabric.microsoft.com/v1/connections" \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" | jq .


echo "🔐 Fetching Customer SPN details from Key Vault..."

SPN_CLIENT_ID=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" \
  --query value -o tsv)

SPN_SECRET=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" \
  --query value -o tsv)

if [ -z "$SPN_CLIENT_ID" ] || [ -z "$SPN_SECRET" ]; then
  echo "❌ Failed to fetch SPN credentials from Key Vault"
  exit 1
fi

echo "🔎 Searching for VNet Gateway: ${GATEWAY_NAME}"

# IMPORTANT: Do NOT use admin/gateways
GATEWAY_LIST=$(curl -s \
  -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN" \
  https://api.powerbi.com/v2.0/myorg/gateways)

echo "$GATEWAY_LIST" | jq .

GATEWAY_ID=$(echo "$GATEWAY_LIST" | jq -r \
  --arg NAME "$GATEWAY_NAME" \
  '.value[] | select(.name==$NAME) | .id')

if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
  echo "❌ Gateway '${GATEWAY_NAME}' not found."
  echo "➡ Ensure Jenkins SPN is added in Manage Users of the VNet gateway."
  exit 1
fi

echo "✅ Gateway ID Found: $GATEWAY_ID"

echo "🔗 Assigning Customer SPN to Gateway..."

curl -s -X POST \
  "https://api.powerbi.com/v2.0/myorg/gateways/${GATEWAY_ID}/users" \
  -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"identifier\": \"${SPN_CLIENT_ID}\",
    \"principalType\": \"App\",
    \"datasourceAccessRight\": \"Admin\"
  }" || true

echo "🚀 Creating VNet Datasource Connection..."

cat <<EOF > vnet_payload.json
{
  "dataSourceType": "AzureDatabricks",
  "connectionDetails": "{\"serverHostName\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}",
  "credentialDetails": {
      "credentialType": "OAuth2",
      "credentials": "{\"clientId\":\"${SPN_CLIENT_ID}\",\"clientSecret\":\"${SPN_SECRET}\",\"tenantId\":\"${AZURE_TENANT_ID}\"}",
      "encryptedConnection": true,
      "encryptionAlgorithm": "None",
      "privacyLevel": "Private"
  },
  "displayName": "${CUSTOMER_CODE}"
}
EOF

HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v2.0/myorg/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_payload.json)

if [ "$HTTP_RESPONSE" -eq 201 ]; then
  echo "🎉 SUCCESS: Fabric VNet Connection Created for ${CUSTOMER_CODE}!"
else
  echo "❌ Failed to create connection. HTTP Status: $HTTP_RESPONSE"
  cat response.json
  exit 1
fi

# #!/bin/bash
# set -e

# echo "🔐 Getting Azure AD Token for Fabric..."



# ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# if [ -z "$ACCESS_TOKEN" ]; then
#   echo "❌ Failed to get Azure token"
#   exit 1
# fi


# echo "🔐 Fetching SPN secrets from Key Vault..."

# SPN_CLIENT_ID=$(az keyvault secret show \
#   --vault-name "$KV_NAME" \
#   --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" \
#   --query value -o tsv)

# SPN_SECRET=$(az keyvault secret show \
#   --vault-name "$KV_NAME" \
#   --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" \
#   --query value -o tsv)

# if [ -z "$SPN_CLIENT_ID" ] || [ -z "$SPN_SECRET" ]; then
#   echo "❌ Failed to fetch SPN secrets"
#   exit 1
# fi

# echo "🚀 Creating Fabric VNet Databricks Connection..."

# HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
#   -X POST "https://api.powerbi.com/v2.0/myorg/connections" \
#   -H "Authorization: Bearer $ACCESS_TOKEN" \
#   -H "Content-Type: application/json" \
#   -d "{
#     \"displayName\": \"${CUSTOMER_CODE}\",
#     \"gatewayClusterName\": \"vnwt-db-fab-fabric-sub\",
#     \"connectionDetails\": {
#       \"type\": \"AzureDatabricks\",
#       \"parameters\": {
#         \"serverHostName\": \"${DATABRICKS_HOST}\",
#         \"httpPath\": \"${DATABRICKS_SQL_PATH}\",
#         \"authenticationType\": \"ServicePrincipal\",
#         \"clientId\": \"${SPN_CLIENT_ID}\",
#         \"clientSecret\": \"${SPN_SECRET}\",
#         \"tenantId\": \"${AZURE_TENANT_ID}\"
#       }
#     },
#     \"privacyLevel\": \"Private\",
#     \"allowCreateArtifact\": true
#   }")


# if [ "$HTTP_RESPONSE" -eq 201 ]; then
#   echo "✅ Fabric VNet Connection Created Successfully"
# else
#   echo "❌ Failed to create connection. HTTP Status: $HTTP_RESPONSE"
#   cat response.json
#   exit 1
# fi
