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
# 1️⃣ Get Azure SPN Application ID
# ------------------------------------------------------------
CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" -o tsv)

if [ -z "$CLIENT_ID" ]; then
  echo "❌ Azure SPN not found: $SPN_NAME"
  exit 1
fi

echo "✅ Azure SPN Client ID: $CLIENT_ID"

# ------------------------------------------------------------
# 2️⃣ Check if SPN already exists in workspace
# ------------------------------------------------------------
EXISTS=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  | jq -r ".Resources[] | select(.applicationId==\"$CLIENT_ID\") | .id")

if [ -n "$EXISTS" ]; then
  echo "ℹ️ SPN already exists in workspace (External)"
  exit 0
fi

# ------------------------------------------------------------
# 3️⃣ Create EXTERNAL (Microsoft Entra ID managed) SPN
# ------------------------------------------------------------
echo "🚀 Creating External (Entra ID managed) SPN in workspace..."

curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  -d "{
        \"applicationId\": \"$CLIENT_ID\",
        \"displayName\": \"$SPN_NAME\"
      }" | jq .

echo "✅ External SPN '$SPN_NAME' added to Databricks workspace"
