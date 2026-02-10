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

# १. Azure ग्रुपला Databricks अकाउंटशी लिंक करणे
echo "🚀 Linking Azure Entra ID Group: ${GROUP_NAME}..."

GROUP_RESPONSE=$(curl -s -X POST "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\",
    \"externalId\": \"${AZURE_OBJ_ID}\"
  }")

GROUP_ID=$(echo $GROUP_RESPONSE | jq -r '.id // empty')

# जर ग्रुप आधीच असेल तर ID मिळवा
if [ "$GROUP_ID" == "null" ] || [ -z "$GROUP_ID" ]; then
    GROUP_ID=$(curl -s -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
      "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups?filter=displayName+eq+%22${GROUP_NAME}%22" \
      | jq -r '.Resources[0].id')
fi

echo "✅ Group ID: $GROUP_ID"

# २. ग्रुप वर्कस्पेसला असाइन करणे
echo "🔗 Assigning group to Workspace: ${WORKSPACE_ID}..."

curl -s -X PUT "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/workspaces/${WORKSPACE_ID}/permissionassignments/principals/${GROUP_ID}" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ "permissions": ["USER"] }'

echo "🎉 Group is now ready in the workspace! Now you can run your Schema Script."
