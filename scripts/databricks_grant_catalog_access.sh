#!/bin/bash
set -e

GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

SQL="GRANT USE CATALOG ON CATALOG \`${CATALOG_NAME}\` TO \`${GROUP_NAME}\`;"

echo "➡️ Granting catalog access to group via SQL API"

RESPONSE=$(curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/sql/statements" \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
    \"statement\": \"$SQL\"
  }")

STATE=$(echo "$RESPONSE" | jq -r '.status.state')

if [ "$STATE" != "SUCCEEDED" ]; then
  echo "❌ Failed to grant catalog access"
  echo "$RESPONSE"
  exit 1
fi

echo "✅ Catalog access granted"
