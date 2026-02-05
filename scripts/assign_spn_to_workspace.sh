#!/bin/bash
set -e

# ============================================================
# REQUIRED ENV (Jenkins / Shell)
# ------------------------------------------------------------
# PRODUCT
# CUSTOMER
# DATABRICKS_ACCOUNT_ID
# DATABRICKS_ACCOUNT_HOST=https://accounts.azuredatabricks.net
# DATABRICKS_ACCOUNT_TOKEN   (ACCOUNT ADMIN PAT)
# DATABRICKS_WORKSPACE_ID
#
# jq installed
# ============================================================

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "=========================================="
echo "Assigning ACCOUNT SPN to Workspace"
echo "SPN Name     : $SPN_NAME"
echo "Workspace ID : $DATABRICKS_WORKSPACE_ID"
echo "=========================================="

# ------------------------------------------------------------
# 1️⃣ Get ACCOUNT-level SPN internal ID
# ------------------------------------------------------------
SPN_ID=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ACCOUNT_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/servicePrincipals" \
  | jq -r ".[] | select(.display_name==\"$SPN_NAME\") | .id")

if [ -z "$SPN_ID" ]; then
  echo "❌ ERROR: Account-level SPN '$SPN_NAME' not found"
  exit 1
fi

echo "✅ Found Account SPN ID: $SPN_ID"

# ------------------------------------------------------------
# 2️⃣ Assign SPN to Workspace (THIS IS UI DROPDOWN ACTION)
# ------------------------------------------------------------
curl -s -X PUT \
  -H "Authorization: Bearer $DATABRICKS_ACCOUNT_TOKEN" \
  -H "Content-Type: application/json" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$DATABRICKS_WORKSPACE_ID/servicePrincipals/$SPN_ID"

echo "✅ SPN '$SPN_NAME' assigned to workspace successfully"
