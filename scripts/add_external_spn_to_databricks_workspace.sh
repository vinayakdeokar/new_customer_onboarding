#!/bin/bash
set -e

# ============================================================
# REQUIRED ENV (Jenkins / Shell)
# ------------------------------------------------------------
# PRODUCT
# CUSTOMER
#
# Azure:
#   az cli logged in (azure_login.sh already ran)
#
# Databricks ACCOUNT:
#   DATABRICKS_ACCOUNT_HOST=https://accounts.azuredatabricks.net
#   DATABRICKS_ACCOUNT_ID
#   DATABRICKS_ACCOUNT_TOKEN   (ACCOUNT ADMIN PAT)
#
# Databricks WORKSPACE:
#   DATABRICKS_WORKSPACE_ID
#
# jq installed
# ============================================================

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "============================================================"
echo "Creating EXTERNAL Databricks SPN & assigning to workspace"
echo "SPN Name     : $SPN_NAME"
echo "Workspace ID : $DATABRICKS_WORKSPACE_ID"
echo "============================================================"

# ------------------------------------------------------------
# 1️⃣ Get Azure Entra ID Application (Client) ID
# ------------------------------------------------------------
CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" -o tsv)

if [ -z "$CLIENT_ID" ]; then
  echo "❌ ERROR: Azure SPN '$SPN_NAME' not found in Entra ID"
  exit 1
fi

echo "✅ Azure SPN Application ID: $CLIENT_ID"

# ------------------------------------------------------------
# 2️⃣ Check if SPN already exists in Databricks ACCOUNT
# ------------------------------------------------------------
ACCOUNT_SPN_ID=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ACCOUNT_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/ServicePrincipals" \
  | jq -r ".Resources[] | select(.applicationId==\"$CLIENT_ID\") | .id")

# ------------------------------------------------------------
# 3️⃣ If not exists → CREATE ACCOUNT-LEVEL SPN (EXTERNAL)
# ------------------------------------------------------------
if [ -z "$ACCOUNT_SPN_ID" ]; then
  echo "🚀 Creating ACCOUNT-level (External) SPN..."

  CREATE_RESP=$(curl -s -X POST \
    -H "Authorization: Bearer $DATABRICKS_ACCOUNT_TOKEN" \
    -H "Content-Type: application/scim+json" \
    "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/ServicePrincipals" \
    -d "{
          \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal\"],
          \"applicationId\": \"$CLIENT_ID\",
          \"displayName\": \"$SPN_NAME\"
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
# 4️⃣ Assign ACCOUNT SPN to WORKSPACE
#     (THIS = UI dropdown + Add)
# ------------------------------------------------------------
echo "🔗 Assigning SPN to workspace..."

curl -s -X PUT \
  -H "Authorization: Bearer $DATABRICKS_ACCOUNT_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$DATABRICKS_WORKSPACE_ID/servicePrincipals/$ACCOUNT_SPN_ID"

echo "============================================================"
echo "✅ DONE"
echo "SPN '$SPN_NAME' added as EXTERNAL and assigned to workspace"
echo "============================================================"
