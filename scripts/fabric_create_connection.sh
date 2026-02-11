#!/bin/bash
set -e

# १. गेटवेचे नाव (तुझ्या स्क्रीनशॉटप्रमाणे)
GATEWAY_NAME="vnwt-db-fab-fabric-sub"

echo "----------------------------------------------------------------"
echo "🔍 AUTO-DISCOVERING GATEWAY ID FOR: $GATEWAY_NAME"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. खऱ्या Gateway ID चा शोध घेणे (List API वापरून)
# SPN ला ॲडमिन राईट्स असल्याने त्याला ही लिस्ट दिसेल
GATEWAY_LIST=$(curl -s -X GET "https://api.powerbi.com/v1.0/myorg/gatewayClusters" \
  -H "Authorization: Bearer $MANAGER_TOKEN")

# नावावरून ID फिल्टर करणे
ACTUAL_GATEWAY_ID=$(echo $GATEWAY_LIST | jq -r ".value[] | select(.name==\"$GATEWAY_NAME\") | .id")

if [ -z "$ACTUAL_GATEWAY_ID" ] || [ "$ACTUAL_GATEWAY_ID" == "null" ]; then
    echo "❌ ERROR: Gateway '$GATEWAY_NAME' not found in your tenant!"
    echo "Available Gateways: $(echo $GATEWAY_LIST | jq -r '.value[].name')"
    exit 1
fi

echo "✅ Found Gateway ID: $ACTUAL_GATEWAY_ID"

# ४. क्रेडेंशियल्स की-वॉल्टमधून मिळवणे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ५. पेलोड तयार करणे
cat <<EOF > auto_vnet_payload.json
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

# ६. फायनल API कॉल
echo "🚀 Creating Datasource on Cluster: $ACTUAL_GATEWAY_ID"
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${ACTUAL_GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @auto_vnet_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' is LIVE!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
