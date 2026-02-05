#!/bin/bash
set -e

# ============================================================
# REQUIRED ENV
# ------------------------------------------------------------
# AZURE_SPN_APP_ID           <-- Azure Entra ID Application ID
#
# DATABRICKS_ACCOUNT_HOST   = https://accounts.azuredatabricks.net
# DATABRICKS_ACCOUNT_ID
# DATABRICKS_ACCOUNT_TOKEN  (Account Admin PAT)
# DATABRICKS_WORKSPACE_ID
#
# jq installed
# ============================================================

APP_ID="$AZURE_SPN_APP_ID"

echo "============================================================"
echo "Adding EXTERNAL SPN to Databricks using Application ID"
echo "Application ID : $APP_ID"
echo "Workspace ID   : $DATABRICKS_WORKSPACE_ID"
echo "============================================================"

# ------------------------------------------------------------
# 1️⃣ Check if SPN already exists at ACCOUNT level
# ------------------------------------------------------------
ACCOUNT_SPN_ID=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ACCOUNT_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/ServicePrincipals" \
  | jq -r ".Resources[] | select(.applicationId==\"$APP_ID\") | .id")

# ------------------------------------------------------------
# 2️⃣ If not exists → create ACCOUNT-level (EXTERNAL) SPN
# ------------------------------------------------------------
if [ -z "$ACCOUNT_SPN_ID" ]; then
  echo "🚀 Creating ACCOUNT-level (External) SPN..."

  CREATE_RESP=$(curl -s -X POST \
    -H "Authorization: Bearer $DATABRICKS_ACCOUNT_TOKEN" \
    -H "Content-Type: application/scim+json" \
    "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/ServicePrincipals" \
    -d "{
          \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal\"],
          \"applicationId\": \"$APP_ID\"
        }")

  ACCOUNT_SPN_ID=$(echo "$CREATE_RESP" | jq -r '.id')

  if [ -z "$ACCOUNT_SPN_ID" ] || [ "$ACCOUNT_SPN_ID" == "null" ]; then
    echo "❌ ERROR: Failed to create account-level SPN"
    echo "$CREATE_RESP"
    exit 1
  fi

  echo "✅ Account-level SPN created"
else
  echo "ℹ️ Account-level SPN already exists"
fi

echo "Account SPN ID: $ACCOUNT_SPN_ID"

# ------------------------------------------------------------
# 3️⃣ Assign ACCOUNT SPN to WORKSPACE
#     (UI: Add service principal → select existing → Add)
# ------------------------------------------------------------
echo "🔗 Assigning SPN to workspace..."

curl -s -X PUT \
  -H "Authorization: Bearer $DATABRICKS_ACCOUNT_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$DATABRICKS_WORKSPACE_ID/servicePrincipals/$ACCOUNT_SPN_ID"

echo "============================================================"
echo "✅ DONE"
echo "SPN added using Application ID and assigned as EXTERNAL"
echo "============================================================"
