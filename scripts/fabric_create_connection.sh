#!/bin/bash
set -e

# १. तुझा गेटवे आयडी
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🚀 FIXING API SCHEMA FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. की-वॉल्टमधून क्रेडेंशियल्स
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. अधिकृत पेलोड (V1.0 Schema - Strict Correction)
# 'dataSourceName' वापरा (कारण एररने Name field मागितली आहे)
# 'dataSourceType' 'Extension' ठेवा (कारण तो VNet कनेक्टर आहे)
cat <<EOF > final_v1_payload.json
{
    "dataSourceName": "${CUSTOMER_CODE}",
    "dataSourceType": "Extension",
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

# ५. अधिकृत API कॉल
echo "📡 Sending request to Official Gateway API..."

HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @final_v1_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' created successfully!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
