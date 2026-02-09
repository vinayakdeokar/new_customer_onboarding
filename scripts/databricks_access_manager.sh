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
: "${DATABRICKS_SQL_WAREHOUSE_ID:?DATABRICKS_SQL_WAREHOUSE_ID missing}"
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
# HELPER: WAIT UNTIL UC SEES GROUP
# ===============================
wait_for_uc_principal () {
  local GROUP="$1"

  for i in {1..10}; do
    RESP=$(curl -s -X POST \
      "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
      -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
        \"statement\": \"SHOW GRANTS ON CATALOG \`${CATALOG_NAME}\`\"
      }")

    if echo "$RESP" | grep -q "\"${GROUP}\""; then
      return 0
    fi
    sleep 5
  done

  echo "❌ UC still does not recognise group $GROUP"
  exit 1
}

# ===============================
# MODE : DEDICATED
# ===============================
if [ "$MODE" = "DEDICATED" ]; then
  GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"
  WAREHOUSE_NAME="wh-${PRODUCT}-${CUSTOMER_CODE}"

  echo "🔐 MODE: DEDICATED"
  echo "Customer : ${CUSTOMER_CODE}"
  echo "Group    : ${GROUP_NAME}"
  echo "Warehouse: ${WAREHOUSE_NAME}"

  run_sql "
  CREATE EXTERNAL LOCATION IF NOT EXISTS bronze_ext_loc
  URL '${STORAGE_BRONZE_ROOT}'
  WITH (STORAGE CREDENTIAL \`azure_uc_cred\`)
  "


  # ------------------------------------------------
  # 1️⃣ BRONZE SCHEMA – EXTERNAL (CREATE TIME ONLY)
  # ------------------------------------------------
  BRONZE_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}_bronze"
  BRONZE_PATH="${STORAGE_BRONZE_ROOT}/${CUSTOMER_CODE}"

  echo "➡️ Creating BRONZE schema as EXTERNAL"
  echo "Schema : ${BRONZE_SCHEMA}"
  echo "Path   : ${BRONZE_PATH}"

  run_sql "CREATE SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\` MANAGED LOCATION '${BRONZE_PATH}'"

  run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\` TO \`${GROUP_NAME}\`"

  # ------------------------------------------------
  # 2️⃣ SILVER & GOLD SCHEMAS (MANAGED)
  # ------------------------------------------------
  for LAYER in silver gold; do
    SCHEMA_NAME="${PRODUCT}-${CUSTOMER_CODE}_${LAYER}"

    echo "➡️ Processing schema: ${SCHEMA_NAME}"

    run_sql "CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\`"
    run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\` TO \`${GROUP_NAME}\`"
  done

  # ------------------------------------------------
  # 3️⃣ CHECK OR CREATE SQL WAREHOUSE
  # ------------------------------------------------
  WAREHOUSE_ID=$(curl -s \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    "${DATABRICKS_HOST}/api/2.0/sql/warehouses" \
    | jq -r ".warehouses[] | select(.name==\"${WAREHOUSE_NAME}\") | .id")

  if [ -z "$WAREHOUSE_ID" ] || [ "$WAREHOUSE_ID" = "null" ]; then
    CREATE_RESP=$(curl -s -X POST \
      "${DATABRICKS_HOST}/api/2.0/sql/warehouses" \
      -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${WAREHOUSE_NAME}\",
        \"cluster_size\": \"Small\",
        \"min_num_clusters\": 1,
        \"max_num_clusters\": 1,
        \"auto_stop_mins\": 10,
        \"enable_serverless_compute\": false
      }")
    WAREHOUSE_ID=$(echo "$CREATE_RESP" | jq -r '.id')
  fi

  curl -s -X PATCH \
    "${DATABRICKS_HOST}/api/2.0/permissions/sql/warehouses/${WAREHOUSE_ID}" \
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
  # 4️⃣ CATALOG ACCESS
  # ------------------------------------------------
  run_sql "GRANT USAGE ON CATALOG \`${CATALOG_NAME}\` TO \`${GROUP_NAME}\`"
  wait_for_uc_principal "${GROUP_NAME}"

  echo "✅ DEDICATED access configured successfully"
fi

echo "🎉 SCRIPT COMPLETED SUCCESSFULLY"
