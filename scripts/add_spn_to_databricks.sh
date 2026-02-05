#!/bin/bash
set -e

# ----------------------------
# Databricks CLI Authentication
# ----------------------------
export DATABRICKS_AUTH_TYPE=azure-client-secret
export DATABRICKS_HOST="${DATABRICKS_HOST}"
export DATABRICKS_CLIENT_ID="${DATABRICKS_CLIENT_ID}"
export DATABRICKS_CLIENT_SECRET="${DATABRICKS_CLIENT_SECRET}"
export DATABRICKS_TENANT_ID="${DATABRICKS_TENANT_ID}"

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
# 1️⃣ Get Azure Entra ID SPN Client ID
# ----------------------------
CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" -o tsv)

if [ -z "$CLIENT_ID" ]; then
  echo "❌ ERROR: Azure SPN '$SPN_NAME' not found in Entra ID"
  exit 1
fi

echo "✅ Found Azure SPN Client ID: $CLIENT_ID"

# ----------------------------
# 2️⃣ Check if SPN already exists in Databricks Workspace
# ----------------------------
if databricks service-principals list --output json | jq -e \
  ".[] | select(.applicationId==\"$CLIENT_ID\")" > /dev/null; then
  echo "ℹ️ SPN already exists in Databricks workspace"
  exit 0
fi

# ----------------------------
# 3️⃣ Add SPN to Databricks Workspace
# ----------------------------
echo "🚀 Creating SPN in Databricks workspace..."

databricks service-principals create \
  --application-id "$CLIENT_ID" \
  --display-name "$SPN_NAME"

echo "✅ SPN '$SPN_NAME' successfully added to Databricks workspace"
echo "=========================================="
