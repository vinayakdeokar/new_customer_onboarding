#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER=$2

if [ -z "$PRODUCT" ] || [ -z "$CUSTOMER" ]; then
  echo "❌ PRODUCT or CUSTOMER missing"
  exit 1
fi

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "🔎 Target Azure SPN name: $SPN_NAME"

# --------------------------------------------------
# Step 1️⃣ Azure login (already done earlier, but safe)
# --------------------------------------------------
az account show > /dev/null

# --------------------------------------------------
# Step 2️⃣ Find Azure SPN by name
# --------------------------------------------------
SPN_CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" \
  -o tsv)

if [ -z "$SPN_CLIENT_ID" ]; then
  echo "❌ Azure SPN not found: $SPN_NAME"
  exit 1
fi

echo "✅ Azure SPN found"
echo "   ➜ Client ID: $SPN_CLIENT_ID"

# --------------------------------------------------
# Step 3️⃣ Databricks CLI login check (same as before)
# --------------------------------------------------
databricks clusters list > /dev/null
echo "✅ Databricks CLI login successful"

# --------------------------------------------------
# Step 4️⃣ Check SPN exists in Databricks
# --------------------------------------------------
echo "🔎 Checking SPN in Databricks workspace..."

EXISTING=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals?filter=applicationId%20eq%20\"$SPN_CLIENT_ID\"")

COUNT=$(echo "$EXISTING" | jq '.Resources | length')

if [ "$COUNT" -gt 0 ]; then
  echo "✅ SPN already exists in Databricks (External). Skipping."
  exit 0
fi

# --------------------------------------------------
# Step 5️⃣ Add SPN to Databricks
# --------------------------------------------------
echo "➕ Adding Azure SPN to Databricks workspace..."

curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"applicationId\": \"$SPN_CLIENT_ID\",
        \"displayName\": \"$SPN_NAME\"
      }"

echo "🎉 SPN added to Databricks (Source = External)"
