#!/bin/bash
set -e

# १. तुझा गेटवे क्लस्टर आयडी (VNet Gateway ID)
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🚀 USING OFFICIAL MICROSOFT REST API FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन (Official Power BI/Fabric Resource)
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. की-वॉल्टमधून क्रेडेंशियल्स मिळवणे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. अधिकृत पेलोड (V1.0 Official Schema)
# टीप: VNet गेटवेसाठी 'credentialDetails' मध्ये क्लस्टर आयडीची 'Key' पुन्हा टाकू नका.
cat <<EOF > official_v1_payload.json
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

# ५. अधिकृत API कॉल (Power BI REST API v1.0)
# हाच तो "Actual API" आहे जो Azure डॉक्युमेंटेशनमध्ये 'Gateways - Create Datasource' साठी दिला आहे.
echo "📡 Sending request to: https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources"

HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @official_v1_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' created using Official v1.0 API!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
