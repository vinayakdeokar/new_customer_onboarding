#!/bin/bash
set -e

# -----------------------------
# Required env validation
# -----------------------------
: "${DATABRICKS_HOST:?missing}"
: "${DATABRICKS_ADMIN_TOKEN:?missing}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?missing}"
: "${CATALOG_NAME:?missing}"
: "${PRODUCT:?missing}"
: "${CUSTOMER_CODE:?missing}"

GROUP="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

BRONZE_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_bronze"
SILVER_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_silver"
GOLD_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_gold"

BRONZE_STORAGE_ROOT="abfss://bronz@stcrmmedicareadv.dfs.core.windows.net/${CUSTOMER_CODE}"

echo "------------------------------------------------"
echo "Catalog   : ${CATALOG_NAME}"
echo "Schemas   : ${BRONZE_SCHEMA} | ${SILVER_SCHEMA} | ${GOLD_SCHEMA}"
echo "Group     : ${GROUP}"
echo "Bronze FS : ${BRONZE_STORAGE_ROOT}"
echo "------------------------------------------------"

# -----------------------------
# SQL payload (serverless safe)
# -----------------------------
SQL=$(cat <<EOF
-- Schemas
CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${BRONZE_SCHEMA};
CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${SILVER_SCHEMA};
CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${GOLD_SCHEMA};

-- Catalog access
GRANT USE CATALOG ON CATALOG ${CATALOG_NAME} TO \`${GROUP}\`;

-- Schema grants
GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOG_NAME}.${BRONZE_SCHEMA} TO \`${GROUP}\`;
GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOG_NAME}.${SILVER_SCHEMA} TO \`${GROUP}\`;
GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOG_NAME}.${GOLD_SCHEMA} TO \`${GROUP}\`;
EOF
)

echo "🚀 Submitting SQL to Databricks Serverless Warehouse..."

RESPONSE=$(curl -s -X POST \
  "${DATABRICKS_HOST}/api/2.0/sql/statements" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"statement\": $(jq -Rs . <<< \"$SQL\"),
    \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
    \"wait_timeout\": \"50s\"
  }")

STATE=$(echo "$RESPONSE" | jq -r '.status.state // empty')

if [[ "$STATE" != "SUCCEEDED" ]]; then
  echo "❌ SQL execution failed"
  echo "$RESPONSE"
  exit 1
fi

echo "✅ Schemas + grants created successfully"
