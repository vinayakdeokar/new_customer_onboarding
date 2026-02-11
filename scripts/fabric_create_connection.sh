#!/bin/bash
set -e

echo "🔐 Getting Manager Token..."
# मॅनेजर SPN चा वापर करून टोकन मिळवणे
MANAGER_ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

echo "🔐 Fetching Customer SPN details from Key Vault..."
SPN_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
SPN_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

echo "🔎 Deep Searching for VNet Gateway ID: vnwt-db-fab-fabric-sub..."

# 'Admin' स्तरावरून सर्व गेटवे शोधण्यासाठी हा API वापरणे आवश्यक आहे
GATEWAY_LIST=$(curl -s -X GET "https://api.powerbi.com/v2.0/myorg/admin/gateways" \
  -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN")

# नावावरून VNet गेटवेचा ID काढणे
GATEWAY_ID=$(echo "$GATEWAY_LIST" | jq -r '.value[] | select(.name=="vnwt-db-fab-fabric-sub") | .id')

# जर वरील लिस्टमध्ये सापडला नाही, तर मॅन्युअल सर्च (Fallback)
if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
    echo "⚠️ Admin API list empty, trying discoverable gateways..."
    GATEWAY_LIST_V2=$(curl -s -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN" "https://api.powerbi.com/v2.0/myorg/gateways")
    GATEWAY_ID=$(echo "$GATEWAY_LIST_V2" | jq -r '.value[] | select(.name=="vnwt-db-fab-fabric-sub") | .id')
fi

if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
  echo "❌ CRITICAL ERROR: Gateway 'vnwt-db-fab-fabric-sub' is not visible even to Manager SPN."
  echo "Please ensure the SPN is added in 'Manage Users' as Admin in Fabric portal."
  exit 1
fi

echo "✅ Gateway ID Found: $GATEWAY_ID"

# १. मॅनेजरने कस्टमर SPN ला परवानगी देणे
echo "🔗 Assigning Customer SPN to Gateway..."
curl -s -X POST "https://api.powerbi.com/v2.0/myorg/gateways/${GATEWAY_ID}/users" \
  -H "Authorization: Bearer $MANAGER_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"identifier\": \"${SPN_CLIENT_ID}\",
    \"principalType\": \"App\",
    \"datasourceAccessRight\": \"Admin\"
  }"

# २. कनेक्शन तयार करणे
echo "🚀 Creating VNet Connection..."
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
  echo "🎉 SUCCESS: Connection Created for ${CUSTOMER_CODE}!"
else
  echo "❌ Failed Status: $HTTP_RESPONSE"
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
