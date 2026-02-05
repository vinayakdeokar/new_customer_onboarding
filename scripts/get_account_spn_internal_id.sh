#!/bin/bash
set -e

[ -f db_env.sh ] && . db_env.sh

# PRODUCT & CUSTOMER must be present
if [ -z "$PRODUCT" ] || [ -z "$CUSTOMER" ]; then
  echo "❌ ERROR: PRODUCT or CUSTOMER not set"
  exit 1
fi

# 🔥 Dynamic SPN name
TARGET_SPN_DISPLAY_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "=========================================="
echo "Fetching ACCOUNT-level SPN"
echo "SPN Name: $TARGET_SPN_DISPLAY_NAME"
echo "=========================================="

RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/scim/v2/ServicePrincipals")

INTERNAL_ID=$(echo "$RESPONSE" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$RESPONSE" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_ID" ]; then
  echo "❌ ERROR: SPN '$TARGET_SPN_DISPLAY_NAME' not found in Databricks ACCOUNT"
  exit 1
fi

echo "✅ Found account-level SPN"
echo "   Internal ID    : $INTERNAL_ID"
echo "   Application ID : $APP_ID"

# Persist for next step
{
  echo "export DATABRICKS_INTERNAL_ID=$INTERNAL_ID"
  echo "export TARGET_APPLICATION_ID=$APP_ID"
  echo "export TARGET_SPN_DISPLAY_NAME=$TARGET_SPN_DISPLAY_NAME"
} >> db_env.sh
