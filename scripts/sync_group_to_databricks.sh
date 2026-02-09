#!/bin/bash
set -e

# ===============================
# REQUIRED ENV VARIABLES
# ===============================
: "${DATABRICKS_ACCOUNT_ID:?Missing DATABRICKS_ACCOUNT_ID}"
: "${DATABRICKS_CLIENT_ID:?Missing DATABRICKS_CLIENT_ID}"
: "${DATABRICKS_CLIENT_SECRET:?Missing DATABRICKS_CLIENT_SECRET}"
: "${DATABRICKS_TENANT_ID:?Missing DATABRICKS_TENANT_ID}"
: "${GROUP_NAME:?Missing GROUP_NAME}"
: "${WORKSPACE_NAME:?Missing WORKSPACE_NAME}"

HOST="https://accounts.azuredatabricks.net"

echo "🔐 Getting OAuth token from Azure AD (Account Admin SPN)..."

# ===============================
# 1️⃣ Get OAuth token (Account-level)
# ===============================
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

# ===============================
# 2️⃣ Find group at Databricks ACCOUNT level
# ===============================
echo "🔎 Looking for Azure AD group in Databricks Account: $GROUP_NAME"

GROUP_ID=$(curl -s -H "$AUTH_HEADER" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName%20eq%20%22$GROUP_NAME%22" \
  | jq -r '.Resources[0].id')

if [[ -z "$GROUP_ID" || "$GROUP_ID" == "null" ]]; then
  echo "❌ Group NOT found at Databricks Account level."
  echo "👉 Ensure Azure Entra ID group exists and SCIM sync is enabled."
  exit 1
fi

echo "✅ Group found"
echo "   Group ID: $GROUP_ID"

# ===============================
# 3️⃣ Get Workspace ID
# ===============================
echo "🔎 Resolving workspace: $WORKSPACE_NAME"

WORKSPACE_ID=$(curl -s -H "$AUTH_HEADER" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces" \
  | jq -r ".workspaces[] | select(.workspace_name==\"$WORKSPACE_NAME\") | .workspace_id")

if [[ -z "$WORKSPACE_ID" || "$WORKSPACE_ID" == "null" ]]; then
  echo "❌ Workspace not found: $WORKSPACE_NAME"
  exit 1
fi

echo "✅ Workspace ID: $WORKSPACE_ID"

# ===============================
# 4️⃣ Assign group to workspace
# ===============================
echo "➡️ Assigning group to workspace (idempotent)"

curl -s -X POST -H "$AUTH_HEADER" \
  "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/groups/$GROUP_ID" \
  >/dev/null

echo "🎉 SUCCESS: Group synced & assigned to Databricks workspace"
