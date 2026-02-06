#!/bin/bash
set -e

: "${PRODUCT:?}"
: "${CUSTOMER_CODE:?}"
: "${DATABRICKS_ACCOUNT_ID:?}"

GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"
ACCOUNTS_URL="https://accounts.azuredatabricks.net"

echo "🔐 Getting Databricks ACCOUNT token via Azure AD..."

ACCOUNT_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

if [ -z "$ACCOUNT_TOKEN" ]; then
  echo "❌ Failed to obtain account token"
  exit 1
fi

echo "➡️ Adding group to Databricks ACCOUNT (metastore): $GROUP_NAME"

curl -s -X POST \
  "$ACCOUNTS_URL/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups" \
  -H "Authorization: Bearer $ACCOUNT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"displayName\": \"${GROUP_NAME}\"
  }" || true

echo "✅ Group ensured at ACCOUNT (metastore) level"
