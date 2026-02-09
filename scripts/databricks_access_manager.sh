#!/bin/bash
set -e

# ===============================
# REQUIRED ENV VARIABLES
# ===============================
: "${MODE:?MODE missing (DEDICATED or SHARED)}"
: "${PRODUCT:?PRODUCT missing}"
: "${CATALOG_NAME:?CATALOG_NAME missing}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST missing}"
: "${DATABRICKS_ADMIN_TOKEN:?DATABRICKS_ADMIN_TOKEN missing}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?DATABRICKS_SQL_WAREHOUSE_ID missing}"   # <-- EXISTING WAREHOUSE ID
: "${STORAGE_BRONZE_ROOT:?STORAGE_BRONZE_ROOT missing}"

if [ "$MODE" = "DEDICATED" ]; then
  : "${CUSTOMER_CODE:?CUSTOMER_CODE missing}"
fi

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
# MODE : DEDICATED
# ===============================
if [ "$MODE" = "DEDICATED" ]; then
  GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

  echo "🔐 MODE: DEDICATED"
  echo "Customer : ${CUSTOMER_CODE}"
  echo "Group    : ${GROUP_NAME}"
  echo "Warehouse: EXISTING (${DATABRICKS_SQL_WAREHOUSE_ID})"

  # ------------------------------------------------
  # 1️⃣ EXTERNAL LOCATION (PER CUSTOMER – BRONZE)
  # ------------------------------------------------
  EXT_LOC_NAME="ext_bronze_${CUSTOMER_CODE}"
  BRONZE_PATH="${STORAGE_BRONZE_ROOT}/${CUSTOMER_CODE}"

  echo "➡️ Creating / Using External Location"
  echo "External Location : ${EXT_LOC_NAME}"
  echo "Path              : ${BRONZE_PATH}"

  run_sql "CREATE EXTERNAL LOCATION IF NOT EXISTS ${EXT_LOC_NAME} URL '${BRONZE_PATH}' WITH (STORAGE CREDENTIAL new_db_test)"

  # ------------------------------------------------
  # 2️⃣ BRONZE SCHEMA (EXTERNAL)
  # ------------------------------------------------
  BRONZE_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_bronze"

  echo "➡️ Creating BRONZE schema"
  echo "Schema : ${BRONZE_SCHEMA}"

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
  # 3️⃣ SILVER & GOLD SCHEMAS (MANAGED)
  # ------------------------------------------------
  for LAYER in silver gold; do
    SCHEMA_NAME="${PRODUCT}-${CUSTOMER_CODE}_${LAYER}"

    echo "➡️ Creating ${LAYER} schema: ${SCHEMA_NAME}"

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
  # 4️⃣ GRANT ACCESS TO EXISTING SQL WAREHOUSE
  # ------------------------------------------------
  echo "➡️ Granting group access to existing warehouse"

  curl -s -X PATCH \
    "${DATABRICKS_HOST}/api/2.0/permissions/sql/warehouses/${DATABRICKS_SQL_WAREHOUSE_ID}" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"access_control_list\": [
        {
          \"group_name\": \"${GROUP_NAME}\",
          \"permission_level\": \"CAN_USE\"
        }
      ]
    }" > /dev/null

  # ------------------------------------------------
  # 5️⃣ CATALOG ACCESS
  # ------------------------------------------------
  run_sql "
  GRANT USAGE
  ON CATALOG \`${CATALOG_NAME}\`
  TO \`${GROUP_NAME}\`
  "

  echo "✅ DEDICATED access configured successfully"
fi

echo "🎉 SCRIPT COMPLETED SUCCESSFULLY"
