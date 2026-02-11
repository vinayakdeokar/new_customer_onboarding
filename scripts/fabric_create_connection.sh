#!/bin/bash
set -e

# --- १. CONFIGURATION ---
# तुझ्या स्क्रीनशॉटनुसार हे आयडी आणि नावे फिक्स आहेत
WORKSPACE_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"
CUSTOMER_CODE="vinayak-005"  
CONNECTION_NAME="conn_db_${CUSTOMER_CODE}"

echo "----------------------------------------------------------------"
echo "🎯 STARTING DEPLOYMENT FOR: $CONNECTION_NAME"
echo "----------------------------------------------------------------"

# --- २. CREDENTIALS FETCHING ---
echo "🔑 Fetching Databricks OAuth credentials from Key Vault..."
# टीप: आपण 'vinayak-005' वापरत आहोत कारण पोर्टलवर तेच नाव आहे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# --- ३. PAYLOAD PREPARATION ---
# VNet Databricks साठी connectionDetails हे स्ट्रिंग फॉरमॅटमध्ये असणे अनिवार्य आहे.
CONN_DETAILS_JSON="{\"server\":\"${DATABRICKS_HOST}\",\"httpPath\":\"${DATABRICKS_SQL_PATH}\"}"

# फायनल JSON पेलोड तयार करणे
cat <<EOF > fabric_payload.json
{
    "datasourceName": "${CONNECTION_NAME}",
    "dataSourceType": "Extension",
    "extensionIdentifier": "Databricks",
    "connectionDetails": $(echo -n "$CONN_DETAILS_JSON" | jq -R .),
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    }
}
EOF

# --- ४. EXECUTION (Using Fabric/Power BI API) ---
echo "📡 Sending Request to Gateway Clusters API..."
# आपण 'Tenant.ReadWrite.All' स्कोप वापरत आहोत
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# VNet गेटवेसाठी gatewayClusters एंडपॉईंट सर्वात रिलायबल आहे
HTTP_STATUS=$(curl -s -o response.json -w "%{http_code}" \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @fabric_payload.json)

# --- ५. RESULT CHECKING ---
echo "----------------------------------------------------------------"
if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CONNECTION_NAME' is now active!"
    echo "✅ Status Code: $HTTP_STATUS"
    rm fabric_payload.json response.json
else
    echo "❌ FAILED: Status Code $HTTP_STATUS"
    echo "📄 Error Details from Fabric:"
    cat response.json
    echo ""
    echo "----------------------------------------------------------------"
    echo "💡 PRO-TIP: If still 404, double-check that 'sp-m360-vinayak-005' 
          has 'Network Contributor' role on VNet 'vnwt-db-fab'."
    exit 1
fi
