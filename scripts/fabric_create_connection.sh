#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
# तुझे कन्फर्म झालेले डिटेल्स
WORKSPACE_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"
CUSTOMER_CODE="vinayak-005"  # अचूक नाव
CONNECTION_NAME="conn_db_${CUSTOMER_CODE}"

echo "----------------------------------------------------------------"
echo "🚀 DIRECT API CONNECTION SETUP (NO CLI INSTALL NEEDED)"
echo "----------------------------------------------------------------"

# --- 2. CREDENTIALS ---
echo "🔑 Fetching credentials..."
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# --- 3. PAYLOAD PREPARATION (THE SECRET SAUCE) ---
# Databricks साठी connectionDetails हे JSON Object नसून 'JSON String' लागते.
# आपण ते आधीच Stringify करत आहोत.
SERVER_VAL="${DATABRICKS_HOST}"
HTTP_PATH_VAL="${DATABRICKS_SQL_PATH}"

# Connection String बनवणे (हे खूप महत्त्वाचे आहे)
CONN_DETAILS_STRING="{\"server\":\"$SERVER_VAL\",\"httpPath\":\"$HTTP_PATH_VAL\"}"

# मुख्य JSON फाइल बनवणे
cat <<EOF > api_payload.json
{
    "datasourceName": "${CUSTOMER_CODE}",
    "dataSourceType": "Extension",
    "extensionIdentifier": "Databricks",
    "gatewayId": "${GATEWAY_ID}",
    "connectionDetails": "$CONN_DETAILS_STRING",
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    }
}
EOF

# --- 4. EXECUTION ---
echo "📡 Sending Request to Power BI/Fabric Gateway API..."
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# आपण 'gatewayClusters' API वापरत आहोत कारण ते VNet साठी आहे
# जर 404 आला तर स्क्रिप्ट थांबणार नाही, आपण Output बघू
HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @api_payload.json)

echo "----------------------------------------------------------------"
if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' created successfully!"
    echo "✅ Status Code: $HTTP_CODE"
    exit 0
else
    echo "❌ FAILED: Status Code $HTTP_CODE"
    echo "📄 Response from Server:"
    cat response.json
    echo ""
    echo "----------------------------------------------------------------"
    echo "💡 TROUBLESHOOTING:"
    echo "1. If 404: The Gateway ID might be wrong. Check URL in Fabric Portal."
    echo "2. If 400: The JSON payload format is incorrect."
    exit 1
fi
