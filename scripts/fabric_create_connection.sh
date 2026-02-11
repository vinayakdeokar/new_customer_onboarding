#!/bin/bash
set -e

# १. पॅरामीटर्स
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"
TENANT_ID="${AZURE_TENANT_ID}"

echo "----------------------------------------------------------------"
echo "🎯 FINALIZING CONNECTION FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन (SPN कडून)
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. की-वॉल्टमधून क्रेडेंशियल्स
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. पेलोड (VNet Gateway साठी 'server' आणि 'path' हेच की-वर्ड्स लागतात)
# टीप: VNet साठी dataSourceType 'Extension' आणि extensionIdentifier 'Databricks' असावा.
cat <<EOF > final_vnet_payload.json
{
    "dataSourceName": "${CUSTOMER_CODE}",
    "dataSourceType": "Extension",
    "extensionIdentifier": "Databricks",
    "connectionDetails": "{\"host\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}",
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    }
}
EOF

# ५. 'gatewayClusters' API वापरणे (VNet साठी हाच एकमेव मार्ग आहे)
echo "📡 Sending Request to Gateway Clusters API..."

# टीप: आपण 'myorg' वापरूया कारण SPN ला टॅनंट ॲक्सेस आहे
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @final_vnet_payload.json)

# ६. निकाल तपासणे
if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' created on VNet Gateway!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    echo "🔍 Error Response:"
    cat response.json
    exit 1
fi
