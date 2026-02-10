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

# १. Azure Object ID मिळवणे (हे आधीच चालत होतं)
echo "🔍 Step 1: Fetching Azure Object ID..."
AZURE_OBJ_ID=$(az ad group show --group "${GROUP_NAME}" --query id --output tsv)

if [ -z "$AZURE_OBJ_ID" ]; then
    echo "❌ ERROR: Azure मध्ये ग्रुप सापडला नाही."
    exit 1
fi
echo "✅ Azure Object ID: $AZURE_OBJ_ID"

# २. [नवीन स्टेप] स्क्रिप्ट रन होतानाच Azure कडून Databricks साठी फ्रेश टोकन घेणे
# हा UUID (2ff814a6...) Azure Databricks चा युनिव्हर्सल आयडी आहे.
echo "🔑 Step 2: Generating Fresh Databricks Token via Azure CLI..."
FRESH_TOKEN=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken --output tsv)

if [ -z "$FRESH_TOKEN" ]; then
    echo "❌ ERROR: Azure CLI वरून टोकन जनरेट करता आला नाही."
    exit 1
fi

# ३. वर्कस्पेसमध्ये ग्रुप तयार करणे (SCIM API)
echo "🚀 Step 3: Creating Group directly in Workspace (${DATABRICKS_HOST})..."

# टीप: इथे आपण $FRESH_TOKEN वापरतोय, जुना $DATABRICKS_TOKEN नाही.
RESPONSE=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
  -H "Authorization: Bearer ${FRESH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\",
    \"externalId\": \"${AZURE_OBJ_ID}\"
  }")

# चेक: ग्रुप तयार झाला किंवा आधीच आहे का?
if echo "$RESPONSE" | grep -q "id"; then
    echo "🎉 SUCCESS: Group created/synced successfully!"
elif echo "$RESPONSE" | grep -q "already exists"; then
    echo "✅ SUCCESS: Group already exists in workspace."
else
    echo "❌ ERROR: Failed to create group."
    echo "Response: $RESPONSE"
    exit 1
fi
