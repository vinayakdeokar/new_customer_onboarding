#!/bin/bash
set -e

# १. तुझा मूळ गेटवे ID (जो आपण आधी वापरला होता)
# हा ID चुकला तरी आपण तोच वापरणार आहोत कारण डिस्कव्हरी काम करत नाहीये
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🚀 FORCING CONNECTION CREATION - THE LAST ATTEMPT"
echo "----------------------------------------------------------------"

# २. टोकन मिळवणे (Resource: Power BI API)
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. पेलोड - VNet साठी 'credentialDetails' मध्ये GATEWAY_ID की असणे अनिवार्य आहे
# आपण 'v2.0' एंडपॉईंटचा प्रयत्न करूया जो 'gatewayClusters' साठी जास्त फ्लेक्सिबल आहे
cat <<EOF > final_vnet_payload.json
{
    "datasourceName": "${CUSTOMER_CODE}",
    "datasourceType": "Extension",
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

# ४. API कॉल - 'v1.0' ऐवजी आपण 'v2.0' ट्राई करूया (जर v1.0 ४०४ देत असेल)
echo "📡 Sending Request to Gateway Clusters API..."
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @final_vnet_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' created!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    echo "📄 Error Details:"
    cat response.json
    
    # जर अजूनही ४०४ आला, तर आपण 'gateways' एंडपॉईंट वापरून बघूया (Fallback)
    echo "🔄 Attempting Fallback to Gateways API..."
    curl -s -o response_fallback.json -X POST "https://api.powerbi.com/v1.0/myorg/gateways/${GATEWAY_ID}/datasources" \
      -H "Authorization: Bearer $MANAGER_TOKEN" \
      -H "Content-Type: application/json" \
      -d @final_vnet_payload.json
    cat response_fallback.json
    exit 1
fi
