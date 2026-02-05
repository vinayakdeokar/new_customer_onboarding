#!/bin/bash
set -e

echo "🔐 Step 1: Setting Databricks authentication context (CLI)"

# Databricks CLI context (already configured in Jenkins)
export DATABRICKS_HOST="$DATABRICKS_HOST"
export DATABRICKS_CLIENT_ID="$DATABRICKS_CLIENT_ID"
export DATABRICKS_CLIENT_SECRET="$DATABRICKS_CLIENT_SECRET"
export DATABRICKS_TENANT_ID="$DATABRICKS_TENANT_ID"

# ---- CLI login validation (same as your old script) ----
databricks clusters list > /dev/null
echo "✅ Databricks CLI login successful"

# -------------------------------------------------------
# Step 2: Validate Admin Token (this is REAL auth for SCIM)
# -------------------------------------------------------
if [ -z "$DATABRICKS_ADMIN_TOKEN" ]; then
  echo "❌ DATABRICKS_ADMIN_TOKEN missing"
  exit 1
fi
echo "✅ Databricks REST auth token available"

# -------------------------------------------------------
# Step 3: Inputs
# -------------------------------------------------------
SPN_CLIENT_ID=$1
SPN_DISPLAY_NAME=$2

if [ -z "$SPN_CLIENT_ID" ]; then
  echo "❌ SPN client ID not provided"
  exit 1
fi

# -------------------------------------------------------
# Step 4: Check SPN exists in Databricks
# -------------------------------------------------------
echo "🔎 Checking if SPN already exists in Databricks workspace..."

EXISTING=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals?filter=applicationId%20eq%20\"$SPN_CLIENT_ID\"")

COUNT=$(echo "$EXISTING" | jq '.Resources | length')

if [ "$COUNT" -gt 0 ]; then
  echo "✅ SPN already exists in Databricks (External). Skipping add."
  exit 0
fi

# -------------------------------------------------------
# Step 5: Add SPN to Databricks
# -------------------------------------------------------
echo "➕ Adding Azure SPN to Databricks workspace..."

curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"applicationId\": \"$SPN_CLIENT_ID\",
        \"displayName\": \"$SPN_DISPLAY_NAME\"
      }"

echo "🎉 SPN successfully added to Databricks (Source = External)"
