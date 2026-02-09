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
    echo "⏳ Waiting for UC to recognise group '$GROUP' (attempt $i)..."

    RESP=$(curl -s -X POST \
      "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
      -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
        \"statement\": \"SHOW GRANTS ON CATALOG \`${CATALOG_NAME}\`\"
      }")

    if echo "$RESP" | grep -q "\"${GROUP}\""; then
      echo "✅ UC principal visible"
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

  # -------------------------------
  # 1️⃣ CREATE + GRANT SCHEMAS (bronze / silver / gold)
  # -------------------------------
  for LAYER in bronze silver gold; do
    SCHEMA_NAME="${PRODUCT}-${CUSTOMER_CODE}_${LAYER}"

    echo "➡️ Processing schema: ${SCHEMA_NAME}"

    # Create schema only if not exists
    run_sql "CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\`"

    # Grant read access (existing + future tables)
    run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\` TO \`${GROUP_NAME}\`"
  done

  BRONZE_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}-bronze-001"
  BRONZE_PATH="${STORAGE_BRONZE_ROOT}/${CUSTOMER_CODE}"
  
  echo "➡️ Attaching external storage to BRONZE schema"
  echo "Schema : ${BRONZE_SCHEMA}"
  echo "Path   : ${BRONZE_PATH}"
  
  run_sql "
    ALTER SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
    SET LOCATION '${BRONZE_PATH}'
  "


  # -------------------------------
  # 2️⃣ CHECK OR CREATE SQL WAREHOUSE
  # -------------------------------
  echo "➡️ Checking if SQL Warehouse ${WAREHOUSE_NAME} exists..."

  WAREHOUSE_ID=$(curl -s \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    "${DATABRICKS_HOST}/api/2.0/sql/warehouses" \
    | jq -r ".warehouses[] | select(.name==\"${WAREHOUSE_NAME}\") | .id")

  if [ -n "$WAREHOUSE_ID" ] && [ "$WAREHOUSE_ID" != "null" ]; then
    echo "✅ Warehouse already exists. Reusing ID: $WAREHOUSE_ID"
  else
    echo "➡️ Creating SQL Warehouse ${WAREHOUSE_NAME}"

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

    if [ -z "$WAREHOUSE_ID" ] || [ "$WAREHOUSE_ID" = "null" ]; then
      echo "❌ Warehouse creation failed"
      echo "$CREATE_RESP"
      exit 1
    fi

    echo "✅ Warehouse created. ID: $WAREHOUSE_ID"
  fi

  # -------------------------------
  # 3️⃣ GRANT WAREHOUSE ACCESS
  # -------------------------------
  echo "➡️ Granting warehouse access to group"

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

  # -------------------------------
  # 4️⃣ UC CATALOG GRANT
  # -------------------------------
  echo "➡️ Granting catalog access (UC warm-up)"
  run_sql "GRANT USAGE ON CATALOG \`${CATALOG_NAME}\` TO \`${GROUP_NAME}\`"

  # -------------------------------
  # 5️⃣ WAIT FOR UC SYNC
  # -------------------------------
  wait_for_uc_principal "${GROUP_NAME}"

  echo "✅ DEDICATED access configured successfully"
fi

# ===============================
# MODE : SHARED
# ===============================
if [ "$MODE" = "SHARED" ]; then
  SCHEMA_NAME="${PRODUCT}_common"

  echo "🔁 MODE: SHARED"
  echo "Schema: ${SCHEMA_NAME}"

  GROUPS=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
      \"statement\": \"SHOW GROUPS\"
    }" \
    | jq -r '.result.data_array[][]' \
    | grep "^grp-${PRODUCT}-.*-users$" || true)

  for GROUP in $GROUPS; do
    run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\` TO \`${GROUP}\`"
  done

  echo "✅ SHARED access configured successfully"
fi

echo "🎉 SCRIPT COMPLETED SUCCESSFULLY"
