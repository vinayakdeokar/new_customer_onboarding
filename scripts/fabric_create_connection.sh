#!/bin/bash
set -e

# --- Configuration ---
# 1. SPN आणि Workspace चे डिटेल्स
# तुझ्या स्क्रीनशॉटनुसार हे फिक्स आहेत
WORKSPACE_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"
# अचूक SPN नाव (तुझ्या पोर्टलनुसार)
CUSTOMER_CODE="vinayak-005"
CONNECTION_NAME="conn_db_${CUSTOMER_CODE}"

echo "----------------------------------------------------------------"
echo "🚀 STARTING FINAL FABRIC CONNECTION SETUP FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# 2. Fabric CLI Extension इंस्टॉल/अपडेट करणे
echo "📦 Installing/Updating Fabric CLI extension..."
az extension add --name fabric --upgrade --allow-preview true --yes &> /dev/null

# 3. Key Vault मधून सीक्रेट्स काढणे
echo "🔑 Fetching credentials from Key Vault..."
# टीप: इथे आपण 'vinayak-005' वापरत आहोत कारण पोर्टलवर तेच नाव आहे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

if [ -z "$CUST_CLIENT_ID" ]; then
    echo "❌ Error: Could not fetch Client ID for $CUSTOMER_CODE"
    exit 1
fi

# 4. पद्धत १: Fabric REST API (सर्वात रिलायबल मार्ग)
# Fabric CLI कधीकधी प्रिव्ह्यूमध्ये असल्याने API जास्त खात्रीशीर आहे
echo "📡 Attempting creation via Fabric API (v1)..."

# टोकन मिळवणे
ACCESS_TOKEN=$(az account get-access-token --resource https://api.fabric.microsoft.com/ --query accessToken -o tsv)

# JSON Payload तयार करणे (Databricks साठी VNet Specific)
# टीप: 'connectionDetails' हे स्ट्रिंग फॉरमॅटमध्येच लागते!
cat <<EOF > api_payload.json
{
  "displayName": "${CONNECTION_NAME}",
  "type": "Databricks",
  "privacyLevel": "Organizational",
  "connectivityType": "Gateway",
  "gatewayId": "${GATEWAY_ID}",
  "connectionDetails": {
      "server": "${DATABRICKS_HOST}",
      "httpPath": "${DATABRICKS_SQL_PATH}"
  },
  "credentialDetails": {
    "credentialType": "Basic",
    "credentials": {
      "username": "${CUST_CLIENT_ID}",
      "password": "${CUST_SECRET}"
    },
    "encryptedConnection": "Encrypted",
    "encryptionAlgorithm": "None",
    "privacyLevel": "Organizational"
  }
}
EOF

# API कॉल (POST /v1/workspaces/{workspaceId}/connections)
# हा 'gatewayClusters' पेक्षा वेगळा आणि नवीन फॅब्रिक नेटिव्ह मार्ग आहे
HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
  -X POST "https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/connections" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @api_payload.json)

if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CONNECTION_NAME' created via API!"
    rm api_payload.json response.json
    exit 0
else
    echo "⚠️ API creation failed with status $HTTP_CODE. Checking details..."
    cat response.json
    echo ""
    echo "🔄 Switching to Plan B: Fabric CLI..."
fi

# 5. पद्धत २: Fabric CLI (Plan B)
# जर API फेल झाले तरच हे रन होईल
az fabric connection create \
    --resource-group "rg-db-fab-test" \
    --workspace-id "$WORKSPACE_ID" \
    --connection-name "$CONNECTION_NAME" \
    --type "Databricks" \
    --gateway-id "$GATEWAY_ID" \
    --connection-details "{ \"server\": \"${DATABRICKS_HOST}\", \"httpPath\": \"${DATABRICKS_SQL_PATH}\" }" \
    --credentials "{ \"username\": \"${CUST_CLIENT_ID}\", \"password\": \"${CUST_SECRET}\" }" \
    --privacy-level "Organizational"

if [ $? -eq 0 ]; then
    echo "🎉 SUCCESS: Connection created via Fabric CLI!"
else
    echo "❌ ALL METHODS FAILED. Please check permissions and gateway status."
    exit 1
fi
