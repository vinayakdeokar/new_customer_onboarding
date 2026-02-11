#!/bin/bash
set -e

# तुझे आयडी आणि कोड
WORKSPACE_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"
CUSTOMER_CODE="vinayak-005" 

echo "----------------------------------------------------------------"
echo "🚀 FINAL ATTEMPT BASED ON MICROSOFT DOCS"
echo "----------------------------------------------------------------"

# १. टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# २. कनेक्शन डिटेल्स (स्ट्रिंग फॉरमॅटमध्ये)
# टीप: लिंकनुसार 'httppath' मधील 'p' स्मॉल असावा
CONN_DETAILS="{\"server\":\"${DATABRICKS_HOST}\",\"httppath\":\"${DATABRICKS_SQL_PATH}\"}"

# ३. पेलोड तयार करणे
cat <<EOF > final_vnet_payload.json
{
    "datasourceName": "${CUSTOMER_CODE}",
    "dataSourceType": "Extension",
    "extensionIdentifier": "Databricks",
    "connectionDetails": $(echo -n "$CONN_DETAILS" | jq -R .),
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    }
}
EOF

# ४. API कॉल - 'gatewayClusters' एंडपॉईंट वापरा (VNet साठी हाच अधिकृत मार्ग आहे)
echo "📡 Sending Request..."
HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @final_vnet_payload.json)

if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection created!"
else
    echo "❌ Status $HTTP_CODE"
    cat response.json
    exit 1
fi
