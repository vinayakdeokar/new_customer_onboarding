# #!/bin/bash
# set -e

# : "${DATABRICKS_ACCOUNT_ID:?Missing}"
# : "${WORKSPACE_ID:?Missing}"
# : "${GROUP_NAME:?Missing}"

# HOST="https://accounts.azuredatabricks.net"

# echo "🔐 Getting Databricks Account token..."
# TOKEN=$(az account get-access-token \
#   --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
#   --query accessToken -o tsv)

# AUTH="Authorization: Bearer $TOKEN"

# echo "🔎 Checking group at ACCOUNT level..."
# GROUP_ID=$(curl -s -H "$AUTH" \
#   "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName eq \"$GROUP_NAME\"" \
#   | jq -r '.Resources[0].id // empty')

# if [ -z "$GROUP_ID" ]; then
#   echo "➕ Creating account-level group..."
#   GROUP_ID=$(curl -s -X POST -H "$AUTH" \
#     "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups" \
#     -H "Content-Type: application/json" \
#     -d "{\"displayName\":\"$GROUP_NAME\"}" \
#     | jq -r '.id')
# fi

# echo "✅ Account group ID: $GROUP_ID"

# echo "🔗 Attaching group to workspace..."
# curl -s -X POST -H "$AUTH" \
#   "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/groups/$GROUP_ID" \
#   >/dev/null

#!/bin/bash
set -e

echo "🔍 Step 1: Fetching Azure Object ID for ${GROUP_NAME}..."

# Azure CLI वापरून मॅन्युअली आयडी न टाकता तो ऑटोमॅटिक मिळवणे
AZURE_OBJ_ID=$(az ad group show --group "${GROUP_NAME}" --query id --output tsv)

if [ -z "$AZURE_OBJ_ID" ]; then
    echo "❌ ERROR: Azure मध्ये '${GROUP_NAME}' हा ग्रुप सापडला नाही."
    exit 1
fi

echo "✅ Azure Object ID Found: $AZURE_OBJ_ID"

# २. ग्रुप अकाउंट लेव्हलला लिंक करणे
echo "🚀 Step 2: Linking to Databricks Account Level..."
CREATE_RESPONSE=$(curl -s -X POST "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\",
    \"externalId\": \"${AZURE_OBJ_ID}\"
  }")

GROUP_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id // empty')

# ३. ग्रुप वर्कस्पेसला असाइन करणे
echo "🔗 Step 3: Assigning group to Workspace: ${WORKSPACE_ID}..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/workspaces/${WORKSPACE_ID}/permissionassignments/principals/${GROUP_ID}" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ "permissions": ["USER"] }')

if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 201 ]; then
    echo "🎉 SUCCESS: Automation Complete! ग्रुप आता स्कीमासाठी तयार आहे."
else
    echo "❌ ERROR: Workspace Assignment फेल झाली (Status: $HTTP_STATUS)."
    exit 1
fi
