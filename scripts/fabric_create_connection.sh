#!/bin/bash
set -e

echo "🔐 Getting Azure AD Token for Fabric/Power BI..."
# VNet Gateway शोधण्यासाठी आणि कनेक्शन बनवण्यासाठी हाच रिसोर्स लागतो
ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

echo "🔐 Fetching SPN secrets from Key Vault..."
SPN_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
SPN_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

echo "🔎 Finding VNet Gateway ID for: vnwt-db-fab-fabric-sub..."
# VNet Gateways साठी विशेष 'v2' एंडपॉईंट वापरणे
GATEWAY_LIST=$(curl -s -X GET "https://api.powerbi.com/v1.0/myorg/gateways" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

# नावावरून गेटवे आयडी शोधणे
GATEWAY_ID=$(echo "$GATEWAY_LIST" | jq -r '.value[] | select(.name=="vnwt-db-fab-fabric-sub") | .id')

if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
  echo "❌ Error: Could not find Gateway ID for 'vnwt-db-fab-fabric-sub'."
  echo "Response received: $GATEWAY_LIST"
  exit 1
fi

echo "🚀 VNet Gateway ID Found: $GATEWAY_ID. Creating Connection..."

# कनेक्शन पेलोड: Virtual Network साठी
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

# गेटवेमध्ये 'Datasource' (Connection) तयार करणे
HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_payload.json)

if [ "$HTTP_RESPONSE" -eq 201 ]; then
  echo "✅ Fabric VNet Connection Created Successfully for ${CUSTOMER_CODE}!"
else
  echo "❌ Failed to create VNet connection. HTTP Status: $HTTP_RESPONSE"
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
#   -X POST "https://api.powerbi.com/v1.0/myorg/connections" \
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
