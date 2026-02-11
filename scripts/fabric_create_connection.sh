#!/bin/bash
echo "----------------------------------------------------------------"
echo "🔐 CHECKING PERMISSIONS FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)
echo "🔍 Token is issued to App ID:"
echo $MANAGER_TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | grep -oP '"appid":"\K[^"]+'

#!/bin/bash
set -e

# १. तुझा Tenant ID आणि Gateway ID
TENANT_ID="${AZURE_TENANT_ID}" # तुझा ॲक्चुअल टॅनंट आयडी इथे हवा
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"

echo "----------------------------------------------------------------"
echo "🔍 DIAGNOSING 401 FOR: $CUSTOMER_CODE"
echo "----------------------------------------------------------------"

# २. टोकन मिळवण्याची नवीन पद्धत (Scope आधारित)
# आपण Power BI चा अधिकृत .default स्कोप वापरूया
MANAGER_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)

# ३. टोकन बरोबर आहे की नाही हे तपासण्यासाठी 'List Gateways' करून बघूया
echo "📡 Testing API Access (List Gateways)..."
TEST_STATUS=$(curl -s -w "%{http_code}" -o test_res.json \
  -X GET "https://api.powerbi.com/v1.0/myorg/gateways" \
  -H "Authorization: Bearer $MANAGER_TOKEN")

if [ "$TEST_STATUS" -ne 200 ]; then
    echo "❌ CRITICAL: SPN cannot even list gateways. Status: $TEST_STATUS"
    cat test_res.json
    exit 1
fi

# ४. आता कनेक्शन बनवण्याचा प्रयत्न (Explicit Tenant ID सह)
echo "🚀 Creating Datasource for $CUSTOMER_CODE..."

# टीप: आपण 'myorg' च्या ऐवजी थेट $TENANT_ID वापरत आहोत
HTTP_STATUS=$(curl -s -w "%{http_code}" -o response.json \
  -X POST "https://api.powerbi.com/v1.0/${TENANT_ID}/gateways/${GATEWAY_ID}/datasources" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @vnet_official_payload.json)

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "🎉 SUCCESS: Connection created!"
else
    echo "❌ FAILED: Status $HTTP_STATUS"
    cat response.json
    exit 1
fi
