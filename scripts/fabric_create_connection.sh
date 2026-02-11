#!/bin/bash
set -e

# ==============================================================================
# CONFIGURATION
# ==============================================================================
GATEWAY_NAME="vnwt-db-fab-fabric-sub"
# जर API ने ID शोधला नाही, तरच हा खालचा ID वापरला जाईल (Optionally Hardcode here)
HARDCODED_GATEWAY_ID="" 

echo "----------------------------------------------------------------"
echo "🚀 STARTING FABRIC CONNECTION AUTOMATION FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# 1️⃣ MANAGER TOKEN मिळवणे (पाइपलाइन SPN)
echo "🔐 Generating Manager Access Token..."
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

if [ -z "$MANAGER_TOKEN" ]; then echo "❌ Failed to get Manager Token"; exit 1; fi

# 2️⃣ KEY VAULT मधून CUSTOMER SECRETS आणणे
echo "🔐 Fetching Customer SPN Credentials from Key Vault ($KV_NAME)..."
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

if [ -z "$CUST_CLIENT_ID" ] || [ -z "$CUST_SECRET" ]; then echo "❌ Failed to fetch secrets from KV"; exit 1; fi

# 3️⃣ GATEWAY ID शोधणे (Deep Search Logic)
echo "🔎 Searching for Gateway ID for: $GATEWAY_NAME..."

# प्रथम VNet Gateway API कॉल करणे
GATEWAY_RESP=$(curl -s -X GET "https://api.powerbi.com/v1.0/myorg/gateways" -H "Authorization: Bearer $MANAGER_TOKEN")
GATEWAY_ID=$(echo "$GATEWAY_RESP" | jq -r --arg n "$GATEWAY_NAME" '.value[] | select(.name==$n) | .id')

# जर सापडला नाही आणि हार्डकोड ID दिला असेल तर तो वापरणे
if [ -z "$GATEWAY_ID" ] && [ -n "$HARDCODED_GATEWAY_ID" ]; then
    echo "⚠️ Auto-discovery failed. Using Hardcoded Gateway ID."
    GATEWAY_ID=$HARDCODED_GATEWAY_ID
fi

if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
    echo "❌ CRITICAL ERROR: Gateway '$GATEWAY_NAME' not found!"
    echo "👉 ACTION REQUIRED: Please add your Pipeline SPN as an ADMIN to the Gateway in Fabric Portal."
    exit 1
fi

echo "✅ Gateway Found! ID: $GATEWAY_ID"

# 4️⃣ CUSTOMER SPN ला GATEWAY वर ॲड करणे (Permission Assignment)
echo "🔗 granting 'ConnectionCreator' permission to Customer SPN..."

PERM_RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/users" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"identifier\": \"${CUST_CLIENT_ID}\",
    \"principalType\": \"App\",
    \"datasourceAccessRight\": \"ReadOverrideEffectiveIdentity\"
  }")

# टीप: ReadOverrideEffectiveIdentity किंवा ConnectionCreator हे रोल वापरावे लागतात.
if [ "$PERM_RESP" -eq 200 ] || [ "$PERM_RESP" -eq 201 ]; then
    echo "✅ Permission Granted Successfully."
else
    echo "⚠️ Warning: Permission assignment returned status $PERM_RESP. Trying to proceed anyway..."
fi

# 5️⃣ CONNECTION तयार करणे (Customer Credentials वापरून)
echo "🚀 Creating Connection '${CUSTOMER_CODE}' on Gateway..."

# JSON Payload तयार करणे (Customer Specific Credentials)
cat <<EOF > connection_payload.json
{
    "dataSourceType": "AzureDatabricks",
    "connectionDetails": "{\"serverHostName\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}",
    "credentialDetails": {
        "credentialType": "OAuth2",
        "credentials": "{\"clientId\":\"${CUST_CLIENT_ID}\",\"clientSecret\":\"${CUST_SECRET}\",\"tenantId\":\"${AZURE_TENANT_ID}\"}",
        "encryptedConnection": true,
        "encryptionAlgorithm": "None",
        "privacyLevel": "Private"
    },
    "displayName": "${CUSTOMER_CODE}"
}
EOF

# API कॉल
CREATE_RESP=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @connection_payload.json)

if [ "$CREATE_RESP" -eq 201 ]; then
    echo "🎉 SUCCESS: Connection '${CUSTOMER_CODE}' created successfully in Fabric!"
else
    echo "❌ FAILED to create connection. Status: $CREATE_RESP"
    cat response.json
    exit 1
fi
# #!/bin/bash
# set -e

# GATEWAY_NAME="vnwt-db-fab-fabric-sub"

# echo "🔐 Getting Manager Token..."
# MANAGER_ACCESS_TOKEN=$(az account get-access-token \
#   --resource https://analysis.windows.net/powerbi/api \
#   --query accessToken -o tsv)

# if [ -z "$MANAGER_ACCESS_TOKEN" ]; then
#   echo "❌ Failed to get Manager token"
#   exit 1
# fi

# echo "🔍 Listing Fabric Connections..."

# FABRIC_TOKEN=$(az account get-access-token \
#   --resource https://analysis.windows.net/powerbi/api \
#   --query accessToken -o tsv)

# curl -s -X GET \
#   "https://api.fabric.microsoft.com/v1/connections" \
#   -H "Authorization: Bearer $FABRIC_TOKEN" \
#   -H "Content-Type: application/json" | jq .


# echo "🔐 Fetching Customer SPN details from Key Vault..."

# SPN_CLIENT_ID=$(az keyvault secret show \
#   --vault-name "$KV_NAME" \
#   --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" \
#   --query value -o tsv)

# SPN_SECRET=$(az keyvault secret show \
#   --vault-name "$KV_NAME" \
#   --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" \
#   --query value -o tsv)

# if [ -z "$SPN_CLIENT_ID" ] || [ -z "$SPN_SECRET" ]; then
#   echo "❌ Failed to fetch SPN credentials from Key Vault"
#   exit 1
# fi

# echo "🔎 Searching for VNet Gateway: ${GATEWAY_NAME}"

# echo "📡 Calling Power BI Gateways API..."

# GATEWAY_LIST=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" \
#   -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN" \
#   https://api.powerbi.com/v2.0/myorg/gateways)

# echo "================ RAW RESPONSE ================"
# echo "$GATEWAY_LIST"
# echo "=============================================="

# HTTP_STATUS=$(echo "$GATEWAY_LIST" | grep HTTP_STATUS | cut -d':' -f2)
# JSON_BODY=$(echo "$GATEWAY_LIST" | sed '/HTTP_STATUS/d')

# echo "HTTP Status: $HTTP_STATUS"

# echo "Parsed JSON:"
# echo "$JSON_BODY" | jq .

# GATEWAY_ID=$(echo "$JSON_BODY" | jq -r \
#   --arg NAME "$GATEWAY_NAME" \
#   '.value[]? | select(.name==$NAME) | .id')

# if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
#   echo "❌ Gateway '${GATEWAY_NAME}' not found in API response."
#   echo "➡ This means Fabric VNet gateway is NOT exposed via Power BI REST API."
#   exit 1
# fi

# echo "✅ Gateway ID Found: $GATEWAY_ID"


# echo "✅ Gateway ID Found: $GATEWAY_ID"

# echo "🔗 Assigning Customer SPN to Gateway..."

# curl -s -X POST \
#   "https://api.powerbi.com/v2.0/myorg/gateways/${GATEWAY_ID}/users" \
#   -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN" \
#   -H "Content-Type: application/json" \
#   -d "{
#     \"identifier\": \"${SPN_CLIENT_ID}\",
#     \"principalType\": \"App\",
#     \"datasourceAccessRight\": \"Admin\"
#   }" || true

# echo "🚀 Creating VNet Datasource Connection..."

# cat <<EOF > vnet_payload.json
# {
#   "dataSourceType": "AzureDatabricks",
#   "connectionDetails": "{\"serverHostName\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}",
#   "credentialDetails": {
#       "credentialType": "OAuth2",
#       "credentials": "{\"clientId\":\"${SPN_CLIENT_ID}\",\"clientSecret\":\"${SPN_SECRET}\",\"tenantId\":\"${AZURE_TENANT_ID}\"}",
#       "encryptedConnection": true,
#       "encryptionAlgorithm": "None",
#       "privacyLevel": "Private"
#   },
#   "displayName": "${CUSTOMER_CODE}"
# }
# EOF

# HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
#   -X POST "https://api.powerbi.com/v2.0/myorg/gateways/${GATEWAY_ID}/datasources" \
#   -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN" \
#   -H "Content-Type: application/json" \
#   -d @vnet_payload.json)

# if [ "$HTTP_RESPONSE" -eq 201 ]; then
#   echo "🎉 SUCCESS: Fabric VNet Connection Created for ${CUSTOMER_CODE}!"
# else
#   echo "❌ Failed to create connection. HTTP Status: $HTTP_RESPONSE"
#   cat response.json
#   exit 1
# fi
