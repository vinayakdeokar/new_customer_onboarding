#!/bin/bash
set -e

# १. गेटवेचे नाव (तुझ्या स्क्रीनशॉटमध्ये आहे तेच)
GATEWAY_NAME="vnwt-db-fab-fabric-sub"

echo "----------------------------------------------------------------"
echo "🔍 AUTO-DISCOVERING GATEWAY ID FOR: $GATEWAY_NAME"
echo "----------------------------------------------------------------"

# २. मॅनेजर टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. सर्व गेटवे क्लस्टर्सची यादी मिळवणे
# नुसार SPN ला API कॉलची परवानगी आहे
GATEWAY_LIST=$(curl -s -X GET "https://api.powerbi.com/v1.0/myorg/gatewayClusters" \
  -H "Authorization: Bearer $MANAGER_TOKEN")

# ४. नावावरून अचूक ID शोधणे
# (यासाठी तुझ्याकडे 'jq' इन्स्टॉल असावे, नसेल तर मला सांग)
ACTUAL_GATEWAY_ID=$(echo $GATEWAY_LIST | jq -r ".value[] | select(.name==\"$GATEWAY_NAME\") | .id")

if [ -z "$ACTUAL_GATEWAY_ID" ] || [ "$ACTUAL_GATEWAY_ID" == "null" ]; then
    echo "❌ ERROR: Gateway '$GATEWAY_NAME' not found in Cluster List!"
    echo "Available Gateways in your Tenant: $(echo $GATEWAY_LIST | jq -r '.value[].name')"
    exit 1
fi

echo "✅ Found Real Gateway ID: $ACTUAL_GATEWAY_ID"

# ५. आता या खऱ्या ID वर कनेक्शन तयार करणे
echo "🚀 Creating Datasource..."
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${ACTUAL_GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "datasourceName": "'${CUSTOMER_CODE}'",
    "datasourceType": "Extension",
    "extensionIdentifier": "Databricks",
    "connectionDetails": "{\"host\":\"'${DATABRICKS_HOST}'\",\"httpPath\":\"'${DATABRICKS_SQL_PATH}'\"}",
    "credentialDetails": {
        "credentialType": "Basic",
        "credentials": "{\"credentialData\":[{\"name\":\"username\",\"value\":\"'${CUST_CLIENT_ID}'\"},{\"name\":\"password\",\"value\":\"'${CUST_SECRET}'\"}]}",
        "encryptedConnection": "Encrypted",
        "encryptionAlgorithm": "None",
        "privacyLevel": "Organizational"
    }
  }')

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection Created!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
