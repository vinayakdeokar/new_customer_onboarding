#!/bin/bash
set -e

# १. तुझा गेटवे क्लस्टर आणि ग्रुप आयडी
GATEWAY_CLUSTER_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"
GROUP_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"

echo "----------------------------------------------------------------"
echo "🚀 AUTOMATING OFFICIAL VNET CONNECTION FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. की-वॉल्टमधून कस्टमर SPN चे क्रेडेंशियल्स काढणे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. अधिकृत (Official) API साठी पेलोड तयार करणे 
# यात 'credentialDetails' मध्ये 'GATEWAY_ID' ची 'Key' लागत नाही, डायरेक्ट व्हॅल्यूज लागतात.
cat <<EOF > official_vnet_payload.json
{
    "dataSourceType": "AzureDatabricks",
    "connectionDetails": "{\"serverHostName\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}",
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    },
    "displayName": "${CUSTOMER_CODE}"
}
EOF

# ५. अधिकृत फॅब्रिक API कॉल
echo "📡 Sending request to Official Group Gateway API..."

# 'v1.0' आणि 'groups' एंडपॉईंट वापरणे सर्वात सुरक्षित आहे
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/groups/${GROUP_ID}/gateways/${GATEWAY_CLUSTER_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @official_vnet_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: VNet Connection created for $CUSTOMER_CODE using Official API!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
