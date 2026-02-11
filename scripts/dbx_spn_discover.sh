#!/bin/bash
set -e

: "${TARGET_SPN_DISPLAY_NAME:?missing}"
: "${DATABRICKS_ACCOUNT_ID:?missing}"

ACCOUNT_ID="$DATABRICKS_ACCOUNT_ID"
ACCOUNTS_BASE_URL="https://accounts.azuredatabricks.net"

echo "🔐 Getting Databricks Account token via Azure AD..."

DB_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

if [ -z "$DB_TOKEN" ]; then
  echo "❌ Failed to get account token"
  exit 1
fi

echo "🔎 Discovering SPN at Account level: $TARGET_SPN_DISPLAY_NAME"

RESPONSE=$(curl -sf -G \
  -H "Authorization: Bearer $DB_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$ACCOUNTS_BASE_URL/api/2.0/accounts/$ACCOUNT_ID/scim/v2/ServicePrincipals")

echo "$RESPONSE" > spn_response.json

INTERNAL_ID=$(jq -r '.Resources[0].id // empty' spn_response.json)
APP_ID=$(jq -r '.Resources[0].applicationId // empty' spn_response.json)

if [ -z "$INTERNAL_ID" ]; then
  echo "❌ SPN not found at account level"
  exit 1
fi

echo "✅ Found SPN"
echo "   Internal ID: $INTERNAL_ID"
echo "   App ID     : $APP_ID"
# Persist values for next stage
echo "export DATABRICKS_INTERNAL_ID=$INTERNAL_ID" > db_env.sh
#echo "export TARGET_SPN_DISPLAY_NAME=$TARGET_SPN_DISPLAY_NAME" >> db_env.sh
echo "export TARGET_SPN_DISPLAY_NAME=\"$(echo "$TARGET_SPN_DISPLAY_NAME" | xargs)\"" >> db_env.sh

#echo "export TARGET_SPN_DISPLAY_NAME=\"$TARGET_SPN_DISPLAY_NAME\"" >> db_env.sh


