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

# १. स्वतःचा (SPN) ID शोधणे
echo "🔎 Identifying Jenkins Service Principal..."
MY_SPN_ID=$(az account show --query user.name -o tsv)
echo "✅ Jenkins SPN Application ID: $MY_SPN_ID"

# २. स्वतःलाच Databricks Workspace मध्ये 'Admin' म्हणून ॲड करण्याचा प्रयत्न करणे
# टीप: यासाठी तुमच्याकडे असलेल्या TOKEN ची गरज पडेल
echo "🛡️ Ensuring Jenkins SPN has Admin rights in Workspace..."
FRESH_TOKEN=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken --output tsv)

# ३. Azure कडून ग्रुपचा Object ID मिळवणे
echo "🔍 Fetching Azure Object ID for ${GROUP_NAME}..."
AZURE_OBJ_ID=$(az ad group show --group "${GROUP_NAME}" --query id --output tsv)

# ४. ग्रुप तयार करणे (SCIM API)
echo "🚀 Creating/Syncing Group..."
RESPONSE=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
  -H "Authorization: Bearer ${FRESH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\",
    \"externalId\": \"${AZURE_OBJ_ID}\"
  }")

if echo "$RESPONSE" | grep -q "id" || echo "$RESPONSE" | grep -q "already exists"; then
    echo "🎉 SUCCESS: Group synced!"
else
    echo "❌ Still getting Error: $RESPONSE"
    echo "💡 जर अजूनही 'Only Admins' एरर येत असेल, तर वरचा $MY_SPN_ID कॉपी करा आणि"
    echo "Databricks Admin Console -> Service Principals मध्ये जाऊन त्याला 'Admin' रोल द्या."
    exit 1
fi
