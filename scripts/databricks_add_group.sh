#!/bin/bash
set -e

GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

echo "➡️ Adding Azure AD group to Databricks workspace: $GROUP_NAME"

curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/Groups" \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"displayName\": \"${GROUP_NAME}\"
  }" || true

echo "✅ Group ensured in Databricks workspace"
