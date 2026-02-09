#!/bin/bash
set -e

# ===============================
# REQUIRED ENV VARIABLES
# ===============================
: "${MODE:?MODE missing (DEDICATED)}"
: "${PRODUCT:?PRODUCT missing}"
: "${CUSTOMER_CODE:?CUSTOMER_CODE missing}"
: "${CATALOG_NAME:?CATALOG_NAME missing}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST missing}"
: "${DATABRICKS_ADMIN_TOKEN:?DATABRICKS_ADMIN_TOKEN missing}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?DATABRICKS_SQL_WAREHOUSE_ID missing}"

# ===============================
# HELPER: RUN SQL (SYNC)
# ===============================
run_sql () {
  local SQL="$1"

  PAYLOAD=$(jq -n \
    --arg wh "$DATABRICKS_SQL_WAREHOUSE_ID" \
    --arg stmt "$SQL" \
    '{
      warehouse_id: $wh,
      statement: $stmt,
      wait_timeout: "30s"
    }'
  )

  RESP=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  STATE=$(echo "$RESP" | jq -r '.status.state // empty')

  if [ "$STATE" != "SUCCEEDED" ]; then
    echo "❌ SQL FAILED"
    echo "$RESP"
    exit 1
  fi
}


# ===============================
# MAIN
# ===============================
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

echo "🔐 MODE      : DEDICATED"
echo "Customer    : ${CUSTOMER_CODE}"
echo "Group       : ${GROUP_NAME}"
echo "Warehouse   : EXISTING (${DATABRICKS_SQL_WAREHOUSE_ID})"
echo "Catalog     : ${CATALOG_NAME}"
echo "Ext Location: ext_bronze_mcr"

# ------------------------------------------------
# 1️⃣ BRONZE SCHEMA (EXTERNAL LOCATION)
# ------------------------------------------------
BRONZE_SCHEMA="${PRODUCT}_${CUSTOMER_CODE}_bronze"

echo "➡️ Creating BRONZE schema"
echo "Schema : ${BRONZE_SCHEMA}"
echo "Path   : ${BRONZE_PATH}"

run_sql "
CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
MANAGED LOCATION '${BRONZE_PATH}'
"

run_sql "
GRANT USAGE, SELECT
ON SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
TO \`${GROUP_NAME}\`
"

# ------------------------------------------------
# 2️⃣ SILVER & GOLD SCHEMAS (MANAGED)
# ------------------------------------------------
for LAYER in silver gold; do
  SCHEMA_NAME="${PRODUCT}_${CUSTOMER_CODE}_${LAYER}"

  echo "➡️ Creating ${LAYER} schema : ${SCHEMA_NAME}"

  run_sql "
  CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\`
  "

  run_sql "
  GRANT USAGE, SELECT
  ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\`
  TO \`${GROUP_NAME}\`
  "
done

# ------------------------------------------------
# 3️⃣ CATALOG ACCESS
# ------------------------------------------------
run_sql "
GRANT USAGE
ON CATALOG \`${CATALOG_NAME}\`
TO \`${GROUP_NAME}\`
"

echo "✅ AUTOMATION COMPLETED SUCCESSFULLY"
