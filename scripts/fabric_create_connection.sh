#!/bin/bash
set -e

# १. तुझ्या कडून मिळालेला गेटवे क्लस्टर आयडी
GATEWAY_CLUSTER_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🚀 AUTOMATING VNET CONNECTION FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन मिळवणे (spn-key-vault-jenk कडून)
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. की-वॉल्टमधून कस्टमर SPN चे क्रेडेंशियल्स काढणे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. पेलोड तयार करणे (जसा तू मॅन्युअली पाठवला आहेस)
cat <<EOF > vnet_datasource_payload.json
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
    "referenceDatasource": false,
    "credentialDetails": {
        "${GATEWAY_CLUSTER_ID}": {
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

# ५. API कॉल करून कनेक्शन तयार करणे
echo "📡 Sending request to Fabric API v2.0..."
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v2.0/myorg/me/gatewayClusters/${GATEWAY_CLUSTER_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_datasource_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: VNet Connection created for $CUSTOMER_CODE!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
