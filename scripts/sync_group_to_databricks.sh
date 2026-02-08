#!/bin/bash
set -e

: "${DATABRICKS_ACCOUNT_ID:?Missing}"
: "${DATABRICKS_SCIM_TOKEN:?Missing}"
: "${GROUP_NAME:?Missing}"
: "${WORKSPACE_NAME:?Missing}"

HOST="https://accounts.azuredatabricks.net"

echo "🚀 Using SCIM token to sync group: $GROUP_NAME"

# 1) Find or create group (SCIM)
GROUP_ID=$(curl -s -H "Authorization: Bearer $DATABRICKS_SCIM_TOKEN" \
  "$HOST/api/2.1/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName%20eq%20%22$GROUP_NAME%22" \
  | jq -r '.Resources[0].id')

if [[ -z "$GROUP_ID" || "$GROUP_ID" == "null" ]]; then
  curl -s -X POST -H "Authorization: Bearer $DATABRICKS_SCIM_TOKEN" \
    -H "Content-Type: application/json" \
    "$HOST/api/2.1/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups" \
    -d "{ \"displayName\": \"$GROUP_NAME\" }"
  sleep 2
  GROUP_ID=$(curl -s -H "Authorization: Bearer $DATABRICKS_SCIM_TOKEN" \
    "$HOST/api/2.1/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName%20eq%20%22$GROUP_NAME%22" \
    | jq -r '.Resources[0].id')
fi

[[ -z "$GROUP_ID" || "$GROUP_ID" == "null" ]] && { echo "❌ Group sync failed"; exit 1; }
echo "✅ Group ID: $GROUP_ID"

# 2) Get workspace id
WORKSPACE_ID=$(curl -s -H "Authorization: Bearer $DATABRICKS_SCIM_TOKEN" \
  "$HOST/api/2.1/accounts/$DATABRICKS_ACCOUNT_ID/workspaces" \
  | jq -r ".workspaces[] | select(.workspace_name==\"$WORKSPACE_NAME\") | .workspace_id")

[[ -z "$WORKSPACE_ID" ]] && { echo "❌ Workspace not found"; exit 1; }
echo "✅ Workspace ID: $WORKSPACE_ID"

# 3) Assign group to workspace
curl -s -X POST -H "Authorization: Bearer $DATABRICKS_SCIM_TOKEN" \
  "$HOST/api/2.1/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/groups/$GROUP_ID"

echo "🎉 SUCCESS"
