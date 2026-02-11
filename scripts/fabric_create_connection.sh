#!/bin/bash
set -e

# १. सेटिंग्ज - तुझ्या स्क्रीनशॉटवरून घेतलेले आयडी
WORKSPACE_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"
# हा तुझा Gateway Cluster ID आहे जो पोर्टलवरून कन्फर्म कर
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2" 
CUSTOMER_CODE="vinayak-005"
CONNECTION_NAME="conn_db_${CUSTOMER_CODE}"

echo "----------------------------------------------------------------"
echo "🎯 CREATING VNET CONNECTION FOR: $CONNECTION_NAME"
echo "----------------------------------------------------------------"

# २. टोकन मिळवणे (Power BI API Resource)
# आपण 'Tenant.ReadWrite.All' वापरत आहोत
ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. क्रेडेंशियल्स मिळवणे
#
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. पेलोड - Microsoft Docs च्या नियमानुसार
# टीप: connectionDetails ही एक एस्केप केलेली (Escaped) JSON स्ट्रिंग असावी लागते.
cat <<EOF > vnet_payload.json
{
    "datasourceName": "${CONNECTION_NAME}",
    "dataSourceType": "Extension",
    "extensionIdentifier": "Databricks",
    "connectionDetails": "{\"server\":\"${DATABRICKS_HOST}\",\"httppath\":\"${DATABRICKS_SQL_PATH}\"}",
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    }
}
EOF

# ५. 'gatewayClusters' API ला कॉल करणे
# हा एंडपॉईंट फॅब्रिकमध्ये 'VNet' गेटवे जोडण्यासाठी वापरला जातो
echo "📡 Sending Request to Fabric Gateway Clusters..."
HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_payload.json)

if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CONNECTION_NAME' तयार झालं आहे!"
    echo "✅ तू आता 'Manage Connections' पेजवर ते तपासू शकतोस."
else
    echo "❌ FAILED: Status $HTTP_CODE"
    cat response.json
    exit 1
fi
