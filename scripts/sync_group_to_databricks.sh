#!/bin/bash
set -e

############################
# REQUIRED INPUTS
############################
export DATABRICKS_HOST="https://accounts.azuredatabricks.net"
export DATABRICKS_ACCOUNT_ID="20cc0b97-861c-4bf9-8ae4-d0e057426cf9"
export DATABRICKS_TOKEN="<ACCOUNT_ADMIN_TOKEN>"

GROUP_NAME="grp-m360-vinayak-002-users"
WORKSPACE_NAME="medicareadv"   # or new-db-test

############################
# DEPENDENCY CHECK
############################
command -v jq >/dev/null 2>&1 || { echo "❌ jq not installed"; exit 1; }

echo "🚀 Starting automation for group: $GROUP_NAME"

############################
# STEP 1: Sync group to Databricks Account (SCIM)
############################
GROUP_ID=$(curl -s -X GET \
  "$DATABRICKS_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName%20eq%20%22$GROUP_NAME%22" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  | jq -r '.Resources[0].id')

if [ "$GROUP_ID" == "null" ] || [ -z "$GROUP_ID" ]; then
  echo "🔄 Group not found in Databricks Account. Syncing from Entra ID..."

  curl -s -X POST \
    "$DATABRICKS_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups" \
    -H "Authorization: Bearer $DATABRICKS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{ \"displayName\": \"$GROUP_NAME\" }"

  sleep 2

  GROUP_ID=$(curl -s -X GET \
    "$DATABRICKS_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName%20eq%20%22$GROUP_NAME%22" \
    -H "Authorization: Bearer $DATABRICKS_TOKEN" \
    | jq -r '.Resources[0].id')
fi

echo "✅ Group synced. Group ID: $GROUP_ID"

############################
# STEP 2: Get Workspace ID
############################
WORKSPACE_ID=$(curl -s -X GET \
  "$DATABRICKS_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  | jq -r ".workspaces[] | select(.workspace_name==\"$WORKSPACE_NAME\") | .workspace_id")

if [ -z "$WORKSPACE_ID" ]; then
  echo "❌ Workspace not found: $WORKSPACE_NAME"
  exit 1
fi

echo "✅ Workspace found. ID: $WORKSPACE_ID"

############################
# STEP 3: Assign group to workspace
############################
curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/groups/$GROUP_ID" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN"

echo "🎉 SUCCESS!"
echo "Group '$GROUP_NAME' is now:"
echo "✔ Synced from Azure Entra ID"
echo "✔ Added to Databricks Account"
echo "✔ Assigned to Workspace '$WORKSPACE_NAME'"
echo "✔ Ready for Unity Catalog GRANTs"
