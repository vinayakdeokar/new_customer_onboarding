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
AZURE_OBJ_ID=$(az ad group show --group "${GROUP_NAME}" --query id --output tsv)

if [ -z "$AZURE_OBJ_ID" ]; then
    echo "❌ ERROR: Azure मध्ये ग्रुप सापडला नाही."
    exit 1
fi
echo "✅ Azure Object ID Found: $AZURE_OBJ_ID"

# स्टेप २: अकाउंट लेव्हलला लिंक करणे
echo "🚀 Step 2: Linking to Databricks Account Level..."
# आपण -v (verbose) जोडलाय जेणेकरून 401 चं कारण समजेल
RESPONSE=$(curl -s -X POST "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\",
    \"externalId\": \"${AZURE_OBJ_ID}\"
  }")

GROUP_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" == "null" ]; then
    echo "ℹ️ Group already exists or searching..."
    GROUP_ID=$(curl -s -X GET "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups?filter=displayName+eq+%22${GROUP_NAME}%22" \
      -H "Authorization: Bearer ${DATABRICKS_TOKEN}" | jq -r '.Resources[0].id // empty')
fi

# स्टेप ३: वर्कस्पेस असाइनमेंट
echo "🔗 Step 3: Assigning group to Workspace: ${WORKSPACE_ID}..."
# इथे आपण पूर्ण एरर मेसेज प्रिंट करू
RESULT=$(curl -s -X PUT "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/workspaces/${WORKSPACE_ID}/permissionassignments/principals/${GROUP_ID}" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ "permissions": ["USER"] }')

if echo "$RESULT" | grep -q "error_code"; then
    echo "❌ ERROR Detail: $RESULT"
    exit 1
fi

echo "🎉 SUCCESS: Automation Complete!"
