#!/bin/bash
set -e

# १. व्हॅल्यूज क्लिन करणे (सर्वात महत्त्वाचे)
# डेटाब्रिक्स होस्टमध्ये https:// नको, फक्त URL हवी (उदा. adb-xxx.azuredatabricks.net)
CLEAN_HOST=$(echo "$DATABRICKS_HOST" | sed -e 's|^https://||' -e 's|/$||')
CLEAN_PATH=$(echo "$DATABRICKS_SQL_PATH" | sed -e 's|^/||')
CLEAN_PATH="/$CLEAN_PATH"

GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🌐 PROVISIONING CONNECTION FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. की-वॉल्टमधून क्रेडेंशियल्स मिळवणे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. अचूक पेलोड (VNet Gateway + Databricks Official Schema)
# टीप: 'host' (LOWERCASE) आणि 'httpPath' (CAMELCASE) हेच की-वर्ड्स हवेत.
cat <<EOF > accurate_payload.json
{
    "dataSourceName": "${CUSTOMER_CODE}",
    "dataSourceType": "Extension",
    "extensionIdentifier": "AzureDatabricks",
    "connectionDetails": "{\"host\":\"${CLEAN_HOST}\",\"httpPath\":\"${CLEAN_PATH}\"}",
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    }
}
EOF

# ५. अधिकृत v1.0 API कॉल
echo "📡 Executing Official Microsoft REST API Call..."

HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @accurate_payload.json)

# ६. रिस्पॉन्स चेक करणे
if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' is now LIVE in Fabric!"
else
    echo "❌ CRITICAL FAILURE: Status $HTTP_STATUS"
    echo "🔍 Error Details:"
    cat response.json
    exit 1
fi
