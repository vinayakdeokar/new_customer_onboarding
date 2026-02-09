#!/bin/bash
set -euo pipefail

: "${DATABRICKS_ACCOUNT_ID:?Missing DATABRICKS_ACCOUNT_ID}"
: "${GROUP_NAME:?Missing GROUP_NAME}"
: "${WORKSPACE_NAME:?Missing WORKSPACE_NAME}"

HOST="https://accounts.azuredatabricks.net"

echo "🔐 Getting Databricks Account token..."

ACCESS_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "❌ Failed to get Databricks Account token"
  exit 1
fi

AUTH_HEADER="Authorization: Bearer $ACCESS_TOKEN"
echo "✅ Token acquired"

# --------------------------------------------------
# 1️⃣ Check group at Databricks ACCOUNT level (NO CREATE)
# --------------------------------------------------
echo "🔎 Checking group at Databricks Account level: $GROUP_NAME"

GROUP_ID=$(curl -s -H "$AUTH_HEADER" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName%20eq%20%22$GROUP_NAME%22" \
  | jq -r '.Resources[0].id // empty')

if [[ -z "$GROUP_ID" ]]; then
  echo "❌ Group NOT present at Databricks Account level"
  echo "👉 This pipeline does NOT create groups"
  echo "👉 Ask platform team to pre-sync this Azure Entra ID group"
  exit 1
fi

echo "✅ Group present at account level"
echo "   ➜ Group ID: $GROUP_ID"

# --------------------------------------------------
# 2️⃣ Resolve Workspace
# --------------------------------------------------
echo "🔎 Resolving workspace: $WORKSPACE_NAME"

WORKSPACE_ID=$(curl -s -H "$AUTH_HEADER" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces" \
  | jq -r ".workspaces[] | select(.workspace_name==\"$WORKSPACE_NAME\") | .workspace_id")

if [[ -z "$WORKSPACE_ID" ]]; then
  echo "❌ Workspace not found: $WORKSPACE_NAME"
  exit 1
fi

echo "✅ Workspace ID: $WORKSPACE_ID"

# --------------------------------------------------
# 3️⃣ Assign group to workspace
# --------------------------------------------------
echo "➡️ Assigning group to workspace..."

curl -s -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/principals/$GROUP_NAME" \
  -d '{"permissions":["USER"]}' \
  >/dev/null

echo "🎉 SUCCESS: Group assigned to Databricks workspace"
