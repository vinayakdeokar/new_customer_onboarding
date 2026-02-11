#!/bin/bash
set -e

# १. गेटवेचे नाव (तुझ्या स्क्रीनशॉटप्रमाणे तंतोतंत)
GATEWAY_NAME="vnwt-db-fab-fabric-sub"

echo "----------------------------------------------------------------"
echo "🔍 UNIVERSAL DISCOVERY FOR: $GATEWAY_NAME"
echo "----------------------------------------------------------------"

# २. टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. ग्लोबल लिस्ट तपासणे (VNet साठी gatewayClusters हाच खरा मार्ग आहे)
# आपण myorg वापरत आहोत कारण SPN ग्लोबल ॲडमिन आहे
GATEWAY_LIST=$(curl -s -X GET "https://api.powerbi.com/v1.0/myorg/gatewayClusters" \
  -H "Authorization: Bearer $MANAGER_TOKEN")

# नावावरून ID शोधणे (Case-insensitive शोधण्यासाठी 'tr' वापरला आहे)
ACTUAL_GATEWAY_ID=$(echo $GATEWAY_LIST | jq -r ".value[] | select(.name==\"$GATEWAY_NAME\") | .id")

if [ -z "$ACTUAL_GATEWAY_ID" ] || [ "$ACTUAL_GATEWAY_ID" == "null" ]; then
    echo "❌ ERROR: Gateway '$GATEWAY_NAME' still not visible to API."
    echo "Available Names in API: $(echo $GATEWAY_LIST | jq -r '.value[].name')"
    exit 1
fi

echo "✅ Success! Found Gateway ID: $ACTUAL_GATEWAY_ID"

# ४. डेटाब्रिक्स कनेक्शन तयार करणे
cat <<EOF > universal_payload.json
{
    "dataSourceName": "${CUSTOMER_CODE}",
    "dataSourceType": "Extension",
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

# ५. फायनल पोस्ट कॉल
echo "🚀 Creating Datasource on $ACTUAL_GATEWAY_ID..."
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${ACTUAL_GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @universal_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 MISSION ACCOMPLISHED: Connection is created!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
