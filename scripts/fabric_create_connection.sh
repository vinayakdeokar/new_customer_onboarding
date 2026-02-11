#!/bin/bash
set -e

# १. डेटा क्लिनिंग (अत्यंत महत्त्वाचे)
# Host मधून https:// काढून टाकणे
CLEAN_HOST=$(echo "$DATABRICKS_HOST" | sed -e 's|^https://||' -e 's|/$||')
# Path स्लॅशने सुरू झालाच पाहिजे
CLEAN_PATH=$(echo "$DATABRICKS_SQL_PATH" | sed -e 's|^/||')
CLEAN_PATH="/$CLEAN_PATH"

GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🚀 FINAL ATTEMPT: OFFICIAL EXTENSION SCHEMA FOR $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. की-वॉल्टमधून क्रेडेंशियल्स मिळवणे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. अधिकृत Gateway API v1.0 पेलोड
# dataSourceType: "Extension" (कारण हा नेटिव्ह टाईप नाही)
# extensionIdentifier: "Databricks" (हेच ते गुपित नाव आहे)
cat <<EOF > final_accurate_payload.json
{
    "dataSourceName": "${CUSTOMER_CODE}",
    "dataSourceType": "Extension",
    "extensionIdentifier": "Databricks",
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

# ५. अधिकृत API कॉल
echo "📡 Target: https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources"

HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @final_accurate_payload.json)

# ६. निकाल तपासणे
if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' is officially created!"
else
    echo "❌ ERROR: Status $HTTP_STATUS"
    echo "📄 Response Details:"
    cat response.json
    exit 1
fi
