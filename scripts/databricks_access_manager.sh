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
run_sql () {
  local SQL="$1"

  RESP=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
      \"statement\": \"${SQL}\"
    }")

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
