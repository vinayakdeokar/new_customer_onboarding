#!/bin/bash
set -e

# ============================================================
# REQUIRED ENV (already present in Jenkins)
# ------------------------------------------------------------
# AZURE_CLIENT_ID
# DATABRICKS_ACCOUNT_ID
# DATABRICKS_ADMIN_TOKEN
# DATABRICKS_WORKSPACE_ID
# ============================================================

DATABRICKS_ACCOUNT_HOST="https://accounts.azuredatabricks.net"
APP_ID="$AZURE_CLIENT_ID"

echo "============================================================"
echo "Assigning Azure Entra ID SPN to Databricks Workspace"
echo "Application ID : $APP_ID"
echo "Workspace ID   : $DATABRICKS_WORKSPACE_ID"
echo "============================================================"

# ------------------------------------------------------------
# 1️⃣ Check / Create ACCOUNT-level SPN (External)
# ------------------------------------------------------------
ACCOUNT_SPN_ID=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/ServicePrincipals" \
  | jq -r ".Resources[] | select(.applicationId==\"$APP_ID\") | .id")

if [ -z "$ACCOUNT_SPN_ID" ]; then
  echo "🚀 Creating ACCOUNT-level (External) SPN..."

  RESP=$(curl -s -X POST \
    -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
    -H "Content-Type: application/scim+json" \
    "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/ServicePrincipals" \
    -d "{
          \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal\"],
          \"applicationId\": \"$APP_ID\"
        }")

  ACCOUNT_SPN_ID=$(echo "$RESP" | jq -r '.id')

  if [ -z "$ACCOUNT_SPN_ID" ] || [ "$ACCOUNT_SPN_ID" == "null" ]; then
    echo "❌ Failed to create account-level SPN"
    echo "$RESP"
    exit 1
  fi

  echo "✅ Account-level SPN created"
else
  echo "ℹ️ Account-level SPN already exists"
fi

echo "Account SPN ID: $ACCOUNT_SPN_ID"

# ------------------------------------------------------------
# 2️⃣ Assign SPN to Workspace (UI dropdown equivalent)
# ------------------------------------------------------------
echo "🔗 Assigning SPN to workspace..."

curl -s -X PUT \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$DATABRICKS_WORKSPACE_ID/servicePrincipals/$ACCOUNT_SPN_ID"

echo "============================================================"
echo "✅ DONE: SPN assigned to workspace as EXTERNAL"
echo "============================================================"
