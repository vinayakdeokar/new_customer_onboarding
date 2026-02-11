#!/bin/bash
set -e

# १. पॅरामीटर्स (तुझ्या स्क्रीनशॉटवरून घेतलेले)
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"
# वर्कस्पेस आयडी
GROUP_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"

echo "----------------------------------------------------------------"
echo "🚀 CREATING CONNECTION VIA FABRIC COMPATIBLE API"
echo "----------------------------------------------------------------"

# २. टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. पेलोड (येथेच आधी चूक होत होती - connectionDetails हा 'String' हवा)
# डेटाब्रिक्ससाठी 'server' आणि 'httppath' असे की-वर्ड्स लागतात
CONNECTION_JSON="{\"server\":\"${DATABRICKS_HOST}\",\"httppath\":\"${DATABRICKS_SQL_PATH}\"}"

# ४. फायनल पेलोड तयार करणे
cat <<EOF > fabric_payload.json
{
    "datasourceName": "${CUSTOMER_CODE}",
    "dataSourceType": "Databricks",
    "connectionDetails": $(echo -n $CONNECTION_JSON | jq -R .),
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"${CUST_CLIENT_ID}\"},{\"name\":\"password\",\"value\":\"${CUST_SECRET}\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    }
}
EOF

# ५. 'gatewayClusters' API वापरून कॉल करणे
echo "📡 Sending Request to Gateway Clusters..."
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @fabric_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' created!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
