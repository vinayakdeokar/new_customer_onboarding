#!/bin/bash
set -euo pipefail

PRODUCT=$1
CUSTOMER=$2

if [ -z "$PRODUCT" ] || [ -z "$CUSTOMER" ]; then
  echo "❌ PRODUCT or CUSTOMER missing"
  exit 1
fi

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "🔎 Target Azure SPN name: $SPN_NAME"

# --------------------------------------------------
# Step 1️⃣ Azure login check
# --------------------------------------------------
az account show > /dev/null

# --------------------------------------------------
# Step 2️⃣ Find Azure SPN
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
# Step 3️⃣ Databricks login check
# --------------------------------------------------
databricks clusters list > /dev/null
echo "✅ Databricks CLI login successful"

# --------------------------------------------------
# Step 4️⃣ Check if SPN already exists in Databricks
# --------------------------------------------------
echo "🔍 Checking if SPN already exists in Databricks workspace..."

EXISTING_SPN=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  | jq -r '.Resources[].applicationId' \
  | grep -w "$SPN_CLIENT_ID" || true)

if [ -n "$EXISTING_SPN" ]; then
  echo "✅ SPN already exists in Databricks – skipping creation"
  exit 0
fi

# --------------------------------------------------
# Step 5️⃣ Create SPN in Databricks
# --------------------------------------------------
echo "➕ Adding Azure SPN to Databricks workspace..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"applicationId\": \"$SPN_CLIENT_ID\",
        \"displayName\": \"$SPN_NAME\"
      }")

if [ "$HTTP_CODE" = "201" ]; then
  echo "🎉 SPN successfully added to Databricks"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "ℹ️ SPN already exists (409 Conflict) – safe to continue"
else
  echo "❌ Failed to add SPN (HTTP $HTTP_CODE)"
  exit 1
fi
