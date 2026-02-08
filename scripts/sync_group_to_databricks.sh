#!/bin/bash
set -e

: "${DATABRICKS_ACCOUNT_ID:?Missing}"
: "${DATABRICKS_CLIENT_ID:?Missing}"
: "${DATABRICKS_CLIENT_SECRET:?Missing}"
: "${DATABRICKS_TENANT_ID:?Missing}"
: "${GROUP_NAME:?Missing}"
: "${WORKSPACE_NAME:?Missing}"

HOST="https://accounts.azuredatabricks.net"

echo "🔐 Getting OAuth token from Azure AD..."

ACCESS_TOKEN=$(curl -s -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$DATABRICKS_CLIENT_ID" \
  -d "client_secret=$DATABRICKS_CLIENT_SECRET" \
  -d "grant_type=client_credentials" \
  -d "scope=2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/.default" \
  "https://login.microsoftonline.com/$DATABRICKS_TENANT_ID/oauth2/v2.0/token" \
  | jq -r '.access_token')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "❌ Failed to get OAuth token"
  exit 1
fi

echo "✅ OAuth token acquired"

AUTH_HEADER="Authorization: Bearer $ACCESS_TOKEN"

echo "🔎 Syncing group: $GROUP_NAME"

# 1. Find or create group
GROUP_ID=$(curl -s -H "$AUTH_HEADER" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName%20eq%20%22$GROUP_NAME%22" \
  | jq -r '.Resources[0].id')

if [[ -z "$GROUP_ID" || "$GROUP_ID" == "null" ]]; then
  curl -s -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups" \
    -d "{ \"displayName\": \"$GROUP_NAME\" }"
  sleep 2
  GROUP_ID=$(curl -s -H "$AUTH_HEADER" \
    "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName%20eq%20%22$GROUP_NAME%22" \
    | jq -r '.Resources[0].id')
fi

[[ -z "$GROUP_ID" || "$GROUP_ID" == "null" ]] && { echo "❌ Group sync failed"; exit 1; }
echo "✅ Group ID: $GROUP_ID"

# 2. Get workspace ID
WORKSPACE_ID=$(curl -s -H "$AUTH_HEADER" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces" \
  | jq -r ".workspaces[] | select(.workspace_name==\"$WORKSPACE_NAME\") | .workspace_id")

[[ -z "$WORKSPACE_ID" ]] && { echo "❌ Workspace not found"; exit 1; }
echo "✅ Workspace ID: $WORKSPACE_ID"

# 3. Assign group to workspace
curl -s -X POST -H "$AUTH_HEADER" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/groups/$GROUP_ID"

echo "🎉 SUCCESS: Group synced & assigned via OAuth"
