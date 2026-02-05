#!/bin/bash
set -e

echo "🔐 Setting Databricks authentication context"

export DATABRICKS_HOST="$DATABRICKS_HOST"
export DATABRICKS_CLIENT_ID="$DATABRICKS_CLIENT_ID"
export DATABRICKS_CLIENT_SECRET="$DATABRICKS_CLIENT_SECRET"
export DATABRICKS_TENANT_ID="$DATABRICKS_TENANT_ID"

# -----------------------------
# 1️⃣ Databricks Login Test
# -----------------------------
databricks clusters list > /dev/null
echo "✅ Databricks login successful"

# -----------------------------
# 2️⃣ Fetch Databricks access token
# -----------------------------
DATABRICKS_TOKEN=$(databricks auth token | jq -r '.access_token')

if [ -z "$DATABRICKS_TOKEN" ] || [ "$DATABRICKS_TOKEN" == "null" ]; then
  echo "❌ Failed to get Databricks access token"
  exit 1
fi

# -----------------------------
# 3️⃣ SPN Inputs
# -----------------------------
SPN_CLIENT_ID=$1
SPN_DISPLAY_NAME=$2

if [ -z "$SPN_CLIENT_ID" ] || [ -z "$SPN_DISPLAY_NAME" ]; then
  echo "❌ SPN client ID or display name missing"
  exit 1
fi

# -----------------------------
# 4️⃣ Check SPN exists in Databricks
# -----------------------------
echo "🔎 Checking SPN in Databricks workspace..."

EXISTING=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals?filter=applicationId%20eq%20\"$SPN_CLIENT_ID\"")

COUNT=$(echo "$EXISTING" | jq '.Resources | length')

if [ "$COUNT" -gt 0 ]; then
  echo "✅ SPN already exists in Databricks (Source = External). Skipping."
  exit 0
fi

# -----------------------------
# 5️⃣ Add SPN to Databricks
# -----------------------------
echo "➕ Adding SPN to Databricks workspace..."

curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"applicationId\": \"$SPN_CLIENT_ID\",
        \"displayName\": \"$SPN_DISPLAY_NAME\"
      }"

echo "🎉 SPN added successfully to Databricks (Source = External)"
