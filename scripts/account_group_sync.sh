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
# Azure CLI वरून ID घेणे
AZURE_OBJ_ID=$(az ad group show --group "${GROUP_NAME}" --query id --output tsv)

if [ -z "$AZURE_OBJ_ID" ]; then
    echo "❌ ERROR: Azure मध्ये ग्रुप सापडला नाही."
    exit 1
fi
echo "✅ Azure Object ID: $AZURE_OBJ_ID"

echo "🚀 Step 2: Creating/Syncing Group directly in Workspace..."

# आपण आता 'Workspace SCIM API' वापरतोय जे तुमच्या Token वर चालते
# हे ग्रुप तयार करेल आणि त्याला Azure ID शी लिंक करेल
RESPONSE=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\",
    \"externalId\": \"${AZURE_OBJ_ID}\"
  }")

# जर ग्रुप आधीच असेल (Error 409) किंवा नवीन बनला, तर आपण चेक करू
if echo "$RESPONSE" | grep -q "id"; then
    echo "🎉 SUCCESS: Group '${GROUP_NAME}' वर्कस्पेसमध्ये ॲड झाला आहे!"
    echo "ℹ️ Details: $RESPONSE"
else
    # जर ग्रुप आधीच असेल तर तो एरर देऊ शकतो, पण ते आपण इग्नोर करू शकतो का ते बघू
    if echo "$RESPONSE" | grep -q "already exists"; then
        echo "✅ SUCCESS: Group आधीच वर्कस्पेसमध्ये आहे."
    else
        echo "❌ ERROR: Group ॲड करताना काहीतरी चूक झाली."
        echo "Response: $RESPONSE"
        exit 1
    fi
fi

echo "✅ Ready for Schema Grant!"
