#!/bin/bash
set -e

# १. पॅरामीटर्स
# लक्षात ठेवा: VNet साठी gatewayClusters एंडपॉईंट वापरावा लागतो
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🚀 PROVISIONING VNET CONNECTION (OFFICIAL CLUSTER API)"
echo "----------------------------------------------------------------"

# २. टोकन मिळवणे (SPN कडून)
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. की-वॉल्टमधून क्रेडेंशियल्स मिळवणे
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# ४. पेलोड - VNet Cluster API साठी 'Extension' प्रकार लागतो
cat <<EOF > vnet_cluster_payload.json
{
    "datasourceName": "${CUSTOMER_CODE}",
    "datasourceType": "Extension",
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

# ५. 'gatewayClusters' एंडपॉईंटवर पोस्ट करणे
# VNet साठी /gateways/ ऐवजी /gatewayClusters/ वापरणे अनिवार्य आहे
echo "📡 Calling Gateway Clusters API..."
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/myorg/gatewayClusters/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_cluster_payload.json)

# ६. रिझल्ट तपासणे
if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: VNet Connection '$CUSTOMER_CODE' created!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
