#!/bin/bash
set -e

[ -f db_env.sh ] && . db_env.sh

# REQUIRED
# PRODUCT
# CUSTOMER
# DATABRICKS_HOST=https://accounts.azuredatabricks.net
# DATABRICKS_TOKEN (Account Admin PAT)
# ACCOUNT_ID

TARGET_SPN_DISPLAY_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "=========================================="
echo "Fetching ACCOUNT-level SPN"
echo "SPN Name : $TARGET_SPN_DISPLAY_NAME"
echo "=========================================="

# 1️⃣ Get Azure SPN Application (Client) ID of TARGET SPN
CLIENT_ID=$(az ad sp list \
  --display-name "$TARGET_SPN_DISPLAY_NAME" \
  --query "[0].appId" -o tsv)

if [ -z "$CLIENT_ID" ]; then
  echo "❌ ERROR: Azure SPN '$TARGET_SPN_DISPLAY_NAME' not found"
  exit 1
fi

echo "✅ Azure SPN Client ID: $CLIENT_ID"

# 2️⃣ Lookup Databricks ACCOUNT SPN by application_id
RESPONSE=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals")

SPN_INTERNAL_ID=$(echo "$RESPONSE" | jq -r \
  ".[] | select(.application_id==\"$CLIENT_ID\") | .id")

if [ -z "$SPN_INTERNAL_ID" ]; then
  echo "❌ ERROR: SPN with application_id $CLIENT_ID not found in Databricks ACCOUNT"
  exit 1
fi

echo "✅ Found account-level SPN"
echo "   Internal ID : $SPN_INTERNAL_ID"

{
  echo "export DATABRICKS_INTERNAL_ID=$SPN_INTERNAL_ID"
  echo "export TARGET_APPLICATION_ID=$CLIENT_ID"
  echo "export TARGET_SPN_DISPLAY_NAME=$TARGET_SPN_DISPLAY_NAME"
} >> db_env.sh
