#!/bin/bash
set -e

# १. तुझ्या URL मधून मिळालेला Group ID आणि Gateway नाव
GROUP_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"
GATEWAY_NAME="vnwt-db-fab-fabric-sub"

echo "----------------------------------------------------------------"
echo "🎯 SCOPING REQUEST TO WORKSPACE: $GROUP_ID"
echo "----------------------------------------------------------------"

# २. टोकन मिळवणे
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. या वर्कस्पेस मधील गेटवेचा खरा ID शोधणे
# आपण 'myorg' ऐवजी 'groups/${GROUP_ID}' वापरत आहोत
GATEWAY_LIST=$(curl -s -X GET "https://api.powerbi.com/v1.0/myorg/groups/${GROUP_ID}/gateways" \
  -H "Authorization: Bearer $MANAGER_TOKEN")

ACTUAL_GATEWAY_ID=$(echo $GATEWAY_LIST | jq -r ".value[] | select(.name==\"$GATEWAY_NAME\") | .id")

if [ -z "$ACTUAL_GATEWAY_ID" ] || [ "$ACTUAL_GATEWAY_ID" == "null" ]; then
    echo "❌ ERROR: Gateway not found in workspace $GROUP_ID"
    exit 1
fi

echo "✅ Found Gateway ID: $ACTUAL_GATEWAY_ID"

# ४. पेलोड (VNet Standard)
cat <<EOF > workspace_vnet_payload.json
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

# ५. फायनल वर्कस्पेस-आधारित API कॉल
echo "🚀 Creating Datasource..."
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/groups/${GROUP_ID}/gateways/${ACTUAL_GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @workspace_vnet_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection '$CUSTOMER_CODE' created in Workspace!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
