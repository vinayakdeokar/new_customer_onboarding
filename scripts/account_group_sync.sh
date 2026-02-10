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

# echo "🎉 Group synced at ACCOUNT level & attached to workspace"

#!/bin/bash
set -e

: "${DATABRICKS_ACCOUNT_ID:?Missing DATABRICKS_ACCOUNT_ID}"
: "${WORKSPACE_ID:?Missing WORKSPACE_ID}"
: "${GROUP_NAME:?Missing GROUP_NAME}"

HOST="https://accounts.azuredatabricks.net"

echo "🔐 Getting Databricks Account token..."
TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

AUTH="Authorization: Bearer $TOKEN"

echo "🔎 Checking Azure Entra ID group at Databricks ACCOUNT level..."
GROUP_ID=$(curl -s -H "$AUTH" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName eq \"$GROUP_NAME\"" \
  | jq -r '.Resources[0].id // empty')

if [ -z "$GROUP_ID" ]; then
  echo "❌ Group '$GROUP_NAME' NOT found at Databricks ACCOUNT level"
  echo "👉 This script will NOT create groups"
  echo "👉 Ensure Azure Entra ID SCIM provisioning is enabled"
  exit 1
fi

echo "✅ Found ACCOUNT-level group"
echo "   Group ID: $GROUP_ID"

echo "🔗 Attaching group to workspace..."
curl -s -X POST -H "$AUTH" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/groups/$GROUP_ID" \
  >/dev/null

echo "🎉 Azure Entra ID group synced & attached to workspace"

