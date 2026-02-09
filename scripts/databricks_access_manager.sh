#!/bin/bash
set -e

# ===============================
# REQUIRED ENV VARIABLES
# ===============================
: "${MODE:?MODE missing}"
: "${PRODUCT:?PRODUCT missing}"
: "${CUSTOMER_CODE:?CUSTOMER_CODE missing}"
: "${CATALOG_NAME:?CATALOG_NAME missing}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST missing}"
: "${DATABRICKS_ADMIN_TOKEN:?DATABRICKS_ADMIN_TOKEN missing}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?DATABRICKS_SQL_WAREHOUSE_ID missing}"

# ===============================
# HELPER: RUN SQL
# ===============================
# safe run_sql using jq to build JSON payload and polling by statement_id
run_sql () {
  local SQL="$1"

  # build JSON payload safely with jq (escapes quotes/newlines/etc.)
  PAYLOAD=$(jq -n --arg wh "$DATABRICKS_SQL_WAREHOUSE_ID" --arg stmt "$SQL" '{warehouse_id:$wh, statement:$stmt}')

  # submit statement
  RESP=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  # debug: show submit response if it doesn't contain statement_id
  STATEMENT_ID=$(echo "$RESP" | jq -r '.statement_id // empty')

  if [ -z "$STATEMENT_ID" ]; then
    echo "❌ Failed to submit SQL (no statement_id). Full response:"
    echo "$RESP" | sed -n '1,200p'
    exit 1
  fi

  # poll for completion (allow enough tries for UC operations)
  for i in {1..40}; do
    STATUS_RESP=$(curl -s -X GET \
      "${DATABRICKS_HOST}/api/2.0/sql/statements/${STATEMENT_ID}" \
      -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}")

    STATE=$(echo "$STATUS_RESP" | jq -r '.status.state // empty')

    if [ "$STATE" = "SUCCEEDED" ]; then
      return 0
    fi

    if [ "$STATE" = "FAILED" ] || [ "$STATE" = "CANCELED" ]; then
      echo "❌ SQL FAILED (statement_id=${STATEMENT_ID}). Full status response:"
      echo "$STATUS_RESP" | sed -n '1,400p'
      exit 1
    fi

    # still running (PENDING / RUNNING)
    sleep 3
  done

  echo "❌ SQL did not finish within timeout for statement_id=${STATEMENT_ID}"
  exit 1
}


# ===============================
# MAIN
# ===============================
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

echo "🔐 MODE: DEDICATED"
echo "Customer : ${CUSTOMER_CODE}"
echo "Group    : ${GROUP_NAME}"
echo "Warehouse: EXISTING (${DATABRICKS_SQL_WAREHOUSE_ID})"

# ------------------------------------------------
# 1️⃣ BRONZE SCHEMA (EXTERNAL via existing ext_bronze)
# ------------------------------------------------
BRONZE_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_bronze"

run_sql "
CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
MANAGED LOCATION '@ext_bronze/${CUSTOMER_CODE}'
"

run_sql "
GRANT USAGE, SELECT
ON SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
TO \`${GROUP_NAME}\`
"

# ------------------------------------------------
# 2️⃣ SILVER & GOLD (MANAGED)
# ------------------------------------------------
for LAYER in silver gold; do
  SCHEMA_NAME="${PRODUCT}-${CUSTOMER_CODE}_${LAYER}"

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
GRANT USAGE ON CATALOG \`${CATALOG_NAME}\`
TO \`${GROUP_NAME}\`
"

echo "🎉 SETUP COMPLETED SUCCESSFULLY"
