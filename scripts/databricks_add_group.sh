#!/bin/bash
set -e

: "${PRODUCT:?}"
: "${CUSTOMER_CODE:?}"
: "${DATABRICKS_HOST:?}"
: "${DATABRICKS_ADMIN_TOKEN:?}"

GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

echo "➡️ Ensuring Databricks workspace group: ${GROUP_NAME}"

# Check if group already exists
EXISTING=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/Groups?filter=displayName%20eq%20\"${GROUP_NAME}\"")

COUNT=$(echo "$EXISTING" | jq '.Resources | length')

if [ "$COUNT" -gt 0 ]; then
  echo "✅ Group already exists in Databricks workspace. Skipping."
  exit 0
fi

# Create group
curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/Groups" \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"displayName\": \"${GROUP_NAME}\"
  }"

echo "✅ Group created in Databricks workspace"
