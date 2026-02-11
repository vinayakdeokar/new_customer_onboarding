#!/bin/bash
set -e

# १. पॅरामीटर्स (DNS चेक करण्यासाठी ping वापरून पाहूया)
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🚀 PROVISIONING VNET CONNECTION (OFFICIAL CLUSTER API): $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. क्रेडेंशियल्स मिळवणे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. पेलोड - हा तोच पेलोड आहे जो VNet Gateway साठी 'Actual' आहे
# टीप: VNet Gateway साठी 'credentialDetails' मध्ये GATEWAY_ID की म्हणून लागतो.
cat <<EOF > vnet_official_payload.json
{
    "datasourceName": "${CUSTOMER_CODE}",
    "datasourceType": "Extension",
    "connectionDetails": "{\"host\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}",
    "singleSignOnType": "None",
    "mashupTestConnectionDetails": {
        "functionName": "Databricks.Catalogs",
        "moduleName": "Databricks",
        "moduleVersion": "2.0.7",
        "parameters": [
            { "name": "host", "type": "text", "isRequired": true, "value": "${DATABRICKS_HOST}" },
            { "name": "httpPath", "type": "text", "isRequired": true, "value": "${DATABRICKS_SQL_PATH}" }
        ]
    },
    "credentialDetails": {
        "${GATEWAY_ID}": {
            "credentialType": "Basic",
            "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
            "encryptedConnection": "Any",
            "privacyLevel": "Organizational",
            "skipTestConnection": true,
            "encryptionAlgorithm": "NONE",
            "credentialSources": []
        }
    }
}
EOF

# ५. 'gatewayClusters' एंडपॉईंट (VNet साठी हाच अधिकृत आहे)
# आपण '/me/' काढले आहे, जे SPN साठी जास्त प्रोफेशनल आहे.
echo "📡 Sending Request to Gateway Clusters API..."

HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v2.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_official_payload.json)

# ६. निकाल
if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' created on VNet Gateway!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
