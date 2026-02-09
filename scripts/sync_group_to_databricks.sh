#!/bin/bash
set -euo pipefail

# ==================================================
# REQUIRED ENV VARIABLES (must be exported by Jenkins)
# ==================================================
: "${DATABRICKS_ACCOUNT_ID:?Missing DATABRICKS_ACCOUNT_ID}"
: "${GROUP_NAME:?Missing GROUP_NAME}"
: "${WORKSPACE_ID:?Missing WORKSPACE_ID}"

HOST="https://accounts.azuredatabricks.net"

echo "==============================================="
echo "🔗 Databricks Group → Workspace ASSIGN ONLY"
echo "Group        : $GROUP_NAME"
echo "Workspace ID : $WORKSPACE_ID"
echo "==============================================="

# --------------------------------------------------
# 1️⃣ Get Databricks Account OAuth Token
# --------------------------------------------------
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
# 2️⃣ Verify Group exists at Databricks ACCOUNT level
# --------------------------------------------------
echo "🔎 Checking group at Databricks Account level..."

GROUP_ID=$(curl -s -H "$AUTH_HEADER" \
"$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups" \
| jq -r ".Resources[] | select(.displayName==\"$GROUP_NAME\") | .id" \
| head -n 1)

if [[ -z "$GROUP_ID" ]]; then
  echo "❌ Group NOT present at Databricks Account level"
  echo "👉 Group must be pre-synced via Databricks Account Console"
  exit 1
fi

echo "✅ Group found"
echo "   ➜ Group ID: $GROUP_ID"

# --------------------------------------------------
# 3️⃣ Assign Group to Workspace (ID based – CORRECT)
# --------------------------------------------------
echo "➡️ Assigning group to workspace..."

curl -s -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/principals/$GROUP_NAME" \
  -d '{"permissions":["USER"]}' \
  >/dev/null

echo "🎉 SUCCESS: Group assigned to Databricks workspace"
