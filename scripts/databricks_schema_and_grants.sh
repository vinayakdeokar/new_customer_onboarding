#!/bin/bash
set -e

# ==================================================
# REQUIRED ENV VARIABLES
# ==================================================
: "${PRODUCT:?Missing PRODUCT}"
: "${CUSTOMER_CODE:?Missing CUSTOMER_CODE}"
: "${CATALOG_NAME:?Missing CATALOG_NAME}"
: "${STORAGE_BRONZE_ROOT:?Missing STORAGE_BRONZE_ROOT}"
: "${DATABRICKS_HOST:?Missing DATABRICKS_HOST}"
: "${DATABRICKS_ADMIN_TOKEN:?Missing DATABRICKS_ADMIN_TOKEN}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?Missing DATABRICKS_SQL_WAREHOUSE_ID}"

# ==================================================
# DERIVED VALUES (GENERIC – ANY CUSTOMER)
# ==================================================
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

BRONZE_SCHEMA="${PRODUCT}_${CUSTOMER_CODE}_bronze"
SILVER_SCHEMA="${PRODUCT}_${CUSTOMER_CODE}_silver"
GOLD_SCHEMA="${PRODUCT}_${CUSTOMER_CODE}_gold"
BRONZE_PATH="${STORAGE_BRONZE_ROOT}/${CUSTOMER_CODE}"

# ==================================================
# HELPER: RUN SQL (SYNC, SAFE JSON)
# ==================================================
run_sql () {
  local SQL="$1"

  PAYLOAD=$(jq -n \
    --arg wh "$DATABRICKS_SQL_WAREHOUSE_ID" \
    --arg stmt "$SQL" \
    '{
      warehouse_id: $wh,
      statement: $stmt,
      wait_timeout: "30s",
      on_wait_timeout: "CONTINUE"
    }'
  )

  RESP=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"
  )

  STATE=$(echo "$RESP" | jq -r '.status.state // "PENDING"')

  if [[ "$STATE" == "FAILED" ]]; then
    echo "❌ SQL FAILED"
    echo "$RESP"
    exit 1
  fi
}

# ==================================================
# LOG
# ==================================================
echo "------------------------------------------------"
echo "Product       : $PRODUCT"
echo "Customer      : $CUSTOMER_CODE"
echo "Group         : $GROUP_NAME"
echo "Catalog       : $CATALOG_NAME"
echo "Bronze Path   : ${BRONZE_PATH}"
echo "------------------------------------------------"

# ==================================================
# 1️⃣ BRONZE SCHEMA (EXTERNAL LOCATION)
# ==================================================
run_sql "
CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
MANAGED LOCATION '${BRONZE_PATH}'
"

# ==================================================
# 2️⃣ SILVER + GOLD SCHEMAS (MANAGED)
# ==================================================
run_sql "
CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SILVER_SCHEMA}\`
"

run_sql "
CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${GOLD_SCHEMA}\`
"

# ==================================================
# 3️⃣ GRANTS
# ==================================================

# ==================================================
# 3️⃣ GRANTS
# ==================================================

# Catalog level
run_sql "
GRANT USAGE
ON CATALOG \`${CATALOG_NAME}\`
TO \`${GROUP_NAME}\`
"

# Bronze
run_sql "
GRANT USE SCHEMA, SELECT, EXECUTE, READ VOLUME
ON SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
TO \`${GROUP_NAME}\`
"

# Silver
run_sql "
GRANT USE SCHEMA, SELECT, EXECUTE, READ VOLUME
ON SCHEMA \`${CATALOG_NAME}\`.\`${SILVER_SCHEMA}\`
TO \`${GROUP_NAME}\`
"

# Gold
run_sql "
GRANT USE SCHEMA, SELECT, EXECUTE, READ VOLUME
ON SCHEMA \`${CATALOG_NAME}\`.\`${GOLD_SCHEMA}\`
TO \`${GROUP_NAME}\`
"


# run_sql "
# GRANT USAGE
# ON CATALOG \`${CATALOG_NAME}\`
# TO \`${GROUP_NAME}\`
# "

# run_sql "
# GRANT USAGE, SELECT
# ON SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
# TO \`${GROUP_NAME}\`
# "

# run_sql "
# GRANT USAGE, SELECT
# ON SCHEMA \`${CATALOG_NAME}\`.\`${SILVER_SCHEMA}\`
# TO \`${GROUP_NAME}\`
# "

# run_sql "
# GRANT USAGE, SELECT
# ON SCHEMA \`${CATALOG_NAME}\`.\`${GOLD_SCHEMA}\`
# TO \`${GROUP_NAME}\`
# "

echo "✅ SCHEMAS CREATED & GRANTS APPLIED SUCCESSFULLY"
