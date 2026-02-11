#!/bin/bash
set -e

echo "🔐 Getting Azure AD Token for Power BI/Fabric..."
# VNet/Gateway API साठी Power BI चा रिसोर्स वापरणे आवश्यक आहे
ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Failed to get Azure token"
  exit 1
fi

echo "🔐 Fetching SPN secrets from Key Vault..."
SPN_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
SPN_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

echo "🚀 Creating Fabric VNet Databricks Connection..."

# VNet Gateway साठी हाच एंडपॉईंट काम करतो
GATEWAY_URL="https://api.powerbi.com/v1.0/myorg/gateways"

# तुझ्या स्क्रीनशॉटनुसार पेलोड
# Gateway Cluster Name: vnwt-db-fab-fabric-sub
# Connection Type: AzureDatabricks
# Privacy Level: Private
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

# टीप: VNet गेटवेवर कनेक्शन बनवण्यासाठी आधी त्या गेटवेचा ID शोधणे आवश्यक असते.
# जर 'vnwt-db-fab-fabric-sub' चा ID माहित असेल तर तो खाली वापरा.
# इथे आपण थेट गेटवे क्लस्टरला 'Push' करण्याचा प्रयत्न करत आहोत.
GATEWAY_ID="तुम्ही_तुमच्या_गेटवेचा_ID_इथे_टाका"

HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "${GATEWAY_URL}/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_payload.json)

if [ "$HTTP_RESPONSE" -eq 201 ]; then
  echo "✅ Fabric VNet Connection Created Successfully!"
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
