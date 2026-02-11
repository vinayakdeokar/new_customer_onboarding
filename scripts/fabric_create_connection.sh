#!/bin/bash
set -e

echo "----------------------------------------------------------------"
echo "🔍 LISTING ALL GATEWAYS & SELECTING: vnwt-db-fab-fabric-sub"
echo "----------------------------------------------------------------"

# १. मॅनेजर टोकन मिळवणे (ज्याला गेटवे ॲडमिन अधिकार आहेत)
echo "🔐 Getting Manager Token..."
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# २. सर्व उपलब्ध गेटवेची यादी तपासणे
echo "🔎 Fetching Gateway List..."
GATEWAY_LIST=$(curl -s -X GET "https://api.powerbi.com/v1.0/myorg/gateways" \
  -H "Authorization: Bearer $MANAGER_TOKEN")

# लिस्ट रिकामी असेल तर ॲडमिन एंडपॉईंट वापरून बघणे
if [ "$(echo "$GATEWAY_LIST" | jq '.value | length')" -eq 0 ]; then
    echo "⚠️ User list empty, trying Admin list..."
    GATEWAY_LIST=$(curl -s -X GET "https://api.powerbi.com/v1.0/myorg/admin/gateways" \
      -H "Authorization: Bearer $MANAGER_TOKEN")
fi

# पूर्ण लिस्ट डिस्प्ले करणे (डिबगिंगसाठी)
echo "📋 Available Gateways in Fabric:"
echo "$GATEWAY_LIST" | jq -r '.value[] | "- Name: \(.name) | ID: \(.id) | Type: \(.type)"'

# ३. 'vnwt-db-fab-fabric-sub' नावाचा गेटवे शोधणे
TARGET_NAME="vnwt-db-fab-fabric-sub"
GATEWAY_ID=$(echo "$GATEWAY_LIST" | jq -r --arg n "$TARGET_NAME" '.value[] | select(.name==$n) | .id')

if [ -z "$GATEWAY_ID" ] || [ "$GATEWAY_ID" == "null" ]; then
    echo "❌ ERROR: Target gateway '$TARGET_NAME' not found in the list above."
    exit 1
fi

echo "✅ Selected Gateway ID: $GATEWAY_ID"

# ४. आता कस्टमर SPN ला अधिकार देणे
echo "🔐 Fetching Customer SPN Secrets for $CUSTOMER_CODE..."
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

echo "🔗 Assigning Customer SPN as Admin/User to the gateway..."
curl -s -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/users" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"identifier\": \"${CUST_CLIENT_ID}\",
    \"principalType\": \"App\",
    \"datasourceAccessRight\": \"Admin\"
  }"

# ५. नवीन कनेक्शन (Datasource) तयार करणे
echo "🚀 Creating VNet Connection: $CUSTOMER_CODE"

cat <<EOF > payload.json
{
    "dataSourceType": "AzureDatabricks",
    "connectionDetails": "{\"serverHostName\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}",
    "credentialDetails": {
        "credentialType": "OAuth2",
        "credentials": "{\"clientId\":\"${CUST_CLIENT_ID}\",\"clientSecret\":\"${CUST_SECRET}\",\"tenantId\":\"${AZURE_TENANT_ID}\"}",
        "encryptedConnection": true,
        "encryptionAlgorithm": "None",
        "privacyLevel": "Private"
    },
    "displayName": "${CUSTOMER_CODE}"
}
EOF

HTTP_CODE=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @payload.json)

if [ "$HTTP_CODE" -eq 201 ]; then
    echo "🎉 SUCCESS: Connection created successfully for ${CUSTOMER_CODE}!"
else
    echo "❌ FAILED. Status: $HTTP_CODE"
    cat response.json
    exit 1
fi
