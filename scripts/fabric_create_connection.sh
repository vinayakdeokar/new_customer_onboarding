#!/bin/bash
set -e

# १. गेटवे आयडी
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🔐 CHECKING PERMISSIONS FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

if [ -z "$MANAGER_TOKEN" ]; then
    echo "❌ ERROR: Failed to get Access Token. Check 'az login'."
    exit 1
fi

# ३. की-वॉल्टमधून क्रेडेंशियल्स
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. पेलोड (VNet Gateway Standard Schema)
cat <<EOF > vnet_payload.json
{
    "datasourceName": "${CUSTOMER_CODE}",
    "datasourceType": "Extension",
    "connectionDetails": "{\"host\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}",
    "credentialDetails": {
        "${GATEWAY_ID}": {
            "credentialType": "Basic",
            "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
            "encryptedConnection": "Any",
            "privacyLevel": "Organizational",
            "skipTestConnection": true,
            "encryptionAlgorithm": "NONE"
        }
    }
}
EOF

# ५. API कॉल (VNet साठी v2.0 हाच मार्ग आहे)
echo "📡 Requesting Fabric API (v2.0)..."
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v2.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection created for $CUSTOMER_CODE!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    echo "🔍 Possible Reason: Service Principal is not an Admin on the Gateway."
    cat response.json
    exit 1
fi
