#!/bin/bash
set -e

# ----------------------------
# Databricks CLI Authentication (PAT)
# ----------------------------
export DATABRICKS_HOST
export DATABRICKS_TOKEN="${DATABRICKS_ADMIN_TOKEN}"

# ----------------------------
# Inputs
# ----------------------------
PRODUCT=$1
CUSTOMER=$2
SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "=========================================="
echo "Adding SPN to Databricks workspace"
echo "SPN Name: $SPN_NAME"
echo "=========================================="

# ----------------------------
# 1️⃣ Get Azure Entra ID SPN App ID
# ----------------------------
CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" -o tsv)

if [ -z "$CLIENT_ID" ]; then
  echo "❌ ERROR: Azure SPN '$SPN_NAME' not found"
  exit 1
fi

echo "✅ Found Azure SPN Client ID: $CLIENT_ID"

# ----------------------------
# 2️⃣ Check if SPN already exists in Databricks workspace
# ----------------------------
if databricks service-principals list --output json | jq -e \
  ".[] | select(.applicationId==\"$CLIENT_ID\")" > /dev/null; then
  echo "ℹ️ SPN already exists in Databricks workspace"
  exit 0
fi

# ----------------------------
# 3️⃣ Create SPN in Databricks workspace
# ----------------------------
echo "🚀 Creating SPN in Databricks workspace..."

databricks service-principals create \
  --application-id "$CLIENT_ID" \
  --display-name "$SPN_NAME"

echo "✅ SPN '$SPN_NAME' successfully added to Databricks workspace"
