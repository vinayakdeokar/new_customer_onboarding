#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
# तुझ्या स्क्रीनशॉटनुसार हे आयडी आणि नावे फिक्स आहेत
WORKSPACE_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"
# हा तुझा VNet Gateway ID
GATEWAY_ID="223ca510-82c0-456f-b5ba-de6ff5c01fd2"
CUSTOMER_CODE="vinayak-005"
CONNECTION_NAME="conn_db_${CUSTOMER_CODE}"

echo "----------------------------------------------------------------"
echo "🛠️ CREATING CONNECTION VIA FABRIC CLI (NO MORE API 404)"
echo "----------------------------------------------------------------"

# --- 2. FETCH CREDENTIALS ---
echo "🔑 Fetching Databricks SPN details..."
#
CUST_CLIENT_ID=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id" --query value -o tsv)
CUST_SECRET=$(az keyvault secret show --vault-name "$KV_NAME" --name "sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret" --query value -o tsv)

# --- 3. FABRIC CLI EXECUTION ---
# आपण 'fabric' extension वापरून थेट कनेक्शन रजिस्टर करणार आहोत.
# हे बरोबर तुझ्या 'Manage Connections' मध्ये दिसायला लागेल.

az fabric connection create \
    --workspace-id "$WORKSPACE_ID" \
    --display-name "$CONNECTION_NAME" \
    --type "Databricks" \
    --gateway-id "$GATEWAY_ID" \
    --connection-details "{
        \"server\": \"${DATABRICKS_HOST}\",
        \"httpPath\": \"${DATABRICKS_SQL_PATH}\"
    }" \
    --authentication-type "Basic" \
    --credentials "{
        \"username\": \"${CUST_CLIENT_ID}\",
        \"password\": \"${CUST_SECRET}\"
    }" \
    --privacy-level "Organizational"

echo "----------------------------------------------------------------"
echo "🎉 SUCCESS: Connection created via Fabric CLI!"
