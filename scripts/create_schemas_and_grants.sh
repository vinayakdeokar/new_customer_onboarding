#!/usr/bin/env bash
set -e

# -----------------------------
# REQUIRED ENV
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

CAT="\`${CATALOG_NAME}\`"
GRP="\`${GROUP}\`"

echo "------------------------------------------------"
echo "Catalog   : ${CATALOG_NAME}"
echo "Schemas   : ${BRONZE_SCHEMA} | ${SILVER_SCHEMA} | ${GOLD_SCHEMA}"
echo "Group     : ${GROUP}"
echo "------------------------------------------------"

SQL_STATEMENTS=(
  "CREATE SCHEMA IF NOT EXISTS ${CAT}.\`${BRONZE_SCHEMA}\`"
  "CREATE SCHEMA IF NOT EXISTS ${CAT}.\`${SILVER_SCHEMA}\`"
  "CREATE SCHEMA IF NOT EXISTS ${CAT}.\`${GOLD_SCHEMA}\`"
  "GRANT USE CATALOG ON CATALOG ${CAT} TO ${GRP}"
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CAT}.\`${BRONZE_SCHEMA}\` TO ${GRP}"
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CAT}.\`${SILVER_SCHEMA}\` TO ${GRP}"
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CAT}.\`${GOLD_SCHEMA}\` TO ${GRP}"
)

for SQL in "${SQL_STATEMENTS[@]}"; do
  echo "Executing SQL: $SQL"

  RESPONSE=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/statements" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"statement\": \"$SQL\",
      \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
      \"wait_timeout\": \"30s\"
    }")

  STATE=$(echo "$RESPONSE" | sed -n 's/.*"state":"\\([^"]*\\)".*/\\1/p')

  if [ "$STATE" != "SUCCEEDED" ]; then
    echo "SQL failed:"
    echo "$RESPONSE"
    exit 1
  fi
done

echo "Schemas and grants created successfully"
