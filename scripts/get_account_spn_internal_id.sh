#!/bin/bash
set -e

[ -f db_env.sh ] && . db_env.sh

# REQUIRED:
# DATABRICKS_HOST=https://accounts.azuredatabricks.net
# DATABRICKS_TOKEN (Account Admin PAT)
# ACCOUNT_ID
# PRODUCT
# CUSTOMER
# CLIENT_ID  (Azure SPN Application ID)

if [ -z "$CLIENT_ID" ]; then
  echo "❌ ERROR: CLIENT_ID (Azure App ID) not set"
  exit 1
fi

TARGET_SPN_DISPLAY_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "=========================================="
echo "Fetching ACCOUNT-level SPN"
echo "SPN Name      : $TARGET_SPN_DISPLAY_NAME"
echo "ApplicationID : $CLIENT_ID"
echo "=========================================="

RESPONSE=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals")

SPN_INTERNAL_ID=$(echo "$RESPONSE" | jq -r ".[] | select(.application_id==\"$CLIENT_ID\") | .id")
APP_ID=$(echo "$RESPONSE" | jq -r ".[] | select(.application_id==\"$CLIENT_ID\") | .application_id")

if [ -z "$SPN_INTERNAL_ID" ] || [ "$SPN_INTERNAL_ID" == "null" ]; then
  echo "❌ ERROR: SPN with application_id $CLIENT_ID not found in Databricks ACCOUNT"
  exit 1
fi

echo "✅ Found account-level SPN"
echo "   Internal ID    : $SPN_INTERNAL_ID"
echo "   Application ID : $APP_ID"

{
  echo "export DATABRICKS_INTERNAL_ID=$SPN_INTERNAL_ID"
  echo "export TARGET_APPLICATION_ID=$APP_ID"
  echo "export TARGET_SPN_DISPLAY_NAME=$TARGET_SPN_DISPLAY_NAME"
} >> db_env.sh
