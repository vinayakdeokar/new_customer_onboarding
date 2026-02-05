#!/bin/bash
set -e

# ============================================================
# REQUIRED ENV
# ------------------------------------------------------------
# PRODUCT
# CUSTOMER
# DATABRICKS_HOST   (https://adb-xxxx.azuredatabricks.net)
# DATABRICKS_TOKEN  (WORKSPACE ADMIN PAT)
#
# az cli logged in
# jq installed
# ============================================================

PRODUCT=$1
CUSTOMER=$2
SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "=========================================="
echo "Adding EXTERNAL (Entra ID managed) SPN"
echo "SPN Name : $SPN_NAME"
echo "=========================================="

# ------------------------------------------------------------
# 1️⃣ Get Azure Entra ID Application ID
# ------------------------------------------------------------
CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" -o tsv)

if [ -z "$CLIENT_ID" ]; then
  echo "❌ ERROR: Azure SPN '$SPN_NAME' not found"
  exit 1
fi

echo "✅ Azure SPN Application ID: $CLIENT_ID"

# ------------------------------------------------------------
# 2️⃣ Check if SPN already exists in workspace
# ------------------------------------------------------------
EXISTING_ID=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/scim+json" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  | jq -r ".Resources[] | select(.applicationId==\"$CLIENT_ID\") | .id")

if [ -n "$EXISTING_ID" ]; then
  echo "ℹ️ External SPN already exists in Databricks workspace"
  exit 0
fi

# ------------------------------------------------------------
# 3️⃣ Create EXTERNAL (Microsoft Entra ID managed) SPN
#     (THIS IS EXACTLY YOUR CURL, MADE DYNAMIC)
# ------------------------------------------------------------
echo "🚀 Creating External SPN in Databricks workspace..."

curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/scim+json" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  -d "{
        \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal\"],
        \"applicationId\": \"$CLIENT_ID\",
        \"displayName\": \"$SPN_NAME\"
      }" | jq .

echo "✅ External (Entra ID managed) SPN '$SPN_NAME' added to Databricks workspace"
