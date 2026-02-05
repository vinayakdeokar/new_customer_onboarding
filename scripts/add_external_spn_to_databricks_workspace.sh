#!/bin/bash
set -e

DATABRICKS_ACCOUNT_HOST="https://accounts.azuredatabricks.net"
APP_ID="$AZURE_CLIENT_ID"

echo "============================================================"
echo "Assigning Azure Entra ID SPN to Databricks Workspace"
echo "Application ID : $APP_ID"
echo "Workspace ID   : $DATABRICKS_WORKSPACE_ID"
echo "============================================================"

# ------------------------------------------------------------
# 1️⃣ List account-level SPNs
# ------------------------------------------------------------
RESP=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/ServicePrincipals")

# 🔍 Debug if response is not as expected
if ! echo "$RESP" | jq -e '.Resources' > /dev/null 2>&1; then
  echo "❌ ERROR: Invalid response from Databricks Account API"
  echo "Response:"
  echo "$RESP"
  exit 1
fi

# ------------------------------------------------------------
# 2️⃣ Find SPN by Application ID
# ------------------------------------------------------------
ACCOUNT_SPN_ID=$(echo "$RESP" | jq -r \
  ".Resources[] | select(.applicationId==\"$APP_ID\") | .id")

# ------------------------------------------------------------
# 3️⃣ Create SPN if not exists
# ------------------------------------------------------------
if [ -z "$ACCOUNT_SPN_ID" ]; then
  echo "🚀 Creating ACCOUNT-level (External) SPN..."

  CREATE_RESP=$(curl -s -X POST \
    -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
    -H "Content-Type: application/scim+json" \
    "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/ServicePrincipals" \
    -d "{
          \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal\"],
          \"applicationId\": \"$APP_ID\"
        }")

  if ! echo "$CREATE_RESP" | jq -e '.id' > /dev/null 2>&1; then
    echo "❌ ERROR: Failed to create account-level SPN"
    echo "$CREATE_RESP"
    exit 1
  fi

  ACCOUNT_SPN_ID=$(echo "$CREATE_RESP" | jq -r '.id')
  echo "✅ Account-level SPN created"
else
  echo "ℹ️ Account-level SPN already exists"
fi

echo "Account SPN ID: $ACCOUNT_SPN_ID"

# ------------------------------------------------------------
# 4️⃣ Assign SPN to workspace
# ------------------------------------------------------------
echo "🔗 Assigning SPN to workspace..."

curl -s -X PUT \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_ACCOUNT_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$DATABRICKS_WORKSPACE_ID/servicePrincipals/$ACCOUNT_SPN_ID"

echo "============================================================"
echo "✅ DONE: SPN assigned to workspace as EXTERNAL"
echo "============================================================"
