#!/bin/bash
set -euo pipefail

# -----------------------------
# Required env vars
# -----------------------------
: "${PRODUCT:?PRODUCT not set}"
: "${CUSTOMER_CODE:?CUSTOMER_CODE not set}"
: "${CATALOG_NAME:?CATALOG_NAME not set}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST not set}"
: "${DATABRICKS_ADMIN_TOKEN:?DATABRICKS_ADMIN_TOKEN not set}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?DATABRICKS_SQL_WAREHOUSE_ID not set}"

# -----------------------------
# Derived names
# -----------------------------
BRONZE_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_bronze"
SILVER_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_silver"
GOLD_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_gold"

echo "------------------------------------------------"
echo "Catalog   : ${CATALOG_NAME}"
echo "Schemas   : ${BRONZE_SCHEMA} | ${SILVER_SCHEMA} | ${GOLD_SCHEMA}"
echo "------------------------------------------------"

# -----------------------------
# SQL payload (IDEMPOTENT)
# -----------------------------
read -r -d '' SQL <<EOF
USE CATALOG \`${CATALOG_NAME}\`;

-- Create schemas (safe on re-run)
CREATE SCHEMA IF NOT EXISTS \`${BRONZE_SCHEMA}\`;
CREATE SCHEMA IF NOT EXISTS \`${SILVER_SCHEMA}\`;
CREATE SCHEMA IF NOT EXISTS \`${GOLD_SCHEMA}\`;

-- Grants (safe on re-run)
GRANT USE CATALOG ON CATALOG \`${CATALOG_NAME}\` TO \`account users\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
TO \`account users\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA \`${CATALOG_NAME}\`.\`${SILVER_SCHEMA}\`
TO \`account users\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA \`${CATALOG_NAME}\`.\`${GOLD_SCHEMA}\`
TO \`account users\`;
EOF

# -----------------------------
# Execute via Databricks SQL API
# -----------------------------
echo "➡️ Executing SQL in Databricks Serverless Warehouse..."

RESPONSE=$(curl -s -X POST \
  "${DATABRICKS_HOST}/api/2.0/sql/statements" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
    \"statement\": $(jq -Rs . <<< \"${SQL}\"),
    \"wait_timeout\": \"30s\"
  }")

STATE=$(echo "$RESPONSE" | jq -r '.status.state')

if [[ "$STATE" != "SUCCEEDED" ]]; then
  echo "❌ SQL FAILED"
  echo "$RESPONSE" | jq .
  exit 1
fi

echo "✅ Schemas + Grants ensured successfully"
