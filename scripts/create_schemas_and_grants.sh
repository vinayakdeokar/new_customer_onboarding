#!/bin/bash
set -e

# -----------------------------
# REQUIRED ENV
# -----------------------------
: "${DATABRICKS_HOST:?}"
: "${DATABRICKS_ADMIN_TOKEN:?}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?}"
: "${CATALOG_NAME:?}"
: "${PRODUCT:?}"
: "${CUSTOMER_CODE:?}"

GROUP="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

BRONZE_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_bronze"
SILVER_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_silver"
GOLD_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_gold"

echo "------------------------------------------------"
echo "Catalog   : ${CATALOG_NAME}"
echo "Schemas   : ${BRONZE_SCHEMA} | ${SILVER_SCHEMA} | ${GOLD_SCHEMA}"
echo "Group     : ${GROUP}"
echo "------------------------------------------------"

# -----------------------------
# SQL STATEMENTS (ONE BY ONE)
# -----------------------------
SQL_STATEMENTS=(
  "CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${BRONZE_SCHEMA}"
  "CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${SILVER_SCHEMA}"
  "CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${GOLD_SCHEMA}"
  "GRANT USE CATALOG ON CATALOG ${CATALOG_NAME} TO \`${GROUP}\`"
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOG_NAME}.${BRONZE_SCHEMA} TO \`${GROUP}\`"
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOG_NAME}.${SILVER_SCHEMA} TO \`${GROUP}\`"
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOG_NAME}.${GOLD_SCHEMA} TO \`${GROUP}\`"
)

# -----------------------------
# EXECUTE SEQUENTIALLY
# -----------------------------
for SQL in "${SQL_STATEMENTS[@]}"; do
  echo "➡️ Executing: $SQL"

  RESP=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/statements" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"statement\": \"$SQL\",
      \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
      \"wait_timeout\": \"30s\"
    }")

  STATE=$(echo "$RESP" | sed -n 's/.*"state":"\\([^"]*\\)".*/\\1/p')

  if [[ "$STATE" != "SUCCEEDED" ]]; then
    echo "❌ Failed SQL: $SQL"
    echo "$RESP"
    exit 1
  fi
done

echo "✅ Schemas + Grants created successfully"
