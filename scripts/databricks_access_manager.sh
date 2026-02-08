#!/bin/bash
set -e

# ===============================
# REQUIRED ENV VARIABLES
# ===============================
: "${MODE:?MODE missing (SHARED or DEDICATED)}"
: "${PRODUCT:?PRODUCT missing}"
: "${CATALOG_NAME:?CATALOG_NAME missing}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST missing}"
: "${DATABRICKS_ADMIN_TOKEN:?DATABRICKS_ADMIN_TOKEN missing}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?DATABRICKS_SQL_WAREHOUSE_ID missing}"

# Required only for DEDICATED
if [ "$MODE" == "DEDICATED" ]; then
  : "${CUSTOMER_CODE:?CUSTOMER_CODE missing}"
fi

# ===============================
# HELPERS
# ===============================
run_sql () {
  local SQL="$1"

  RESPONSE=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
      \"statement\": \"${SQL}\"
    }"
  )

  STATE=$(echo "$RESPONSE" | jq -r '.status.state // empty')
  if [ "$STATE" != "SUCCEEDED" ]; then
    echo "❌ SQL FAILED"
    echo "$RESPONSE"
    exit 1
  fi
}

# ===============================
# MODE : SHARED
# ===============================
if [ "$MODE" == "SHARED" ]; then
  SCHEMA_NAME="${PRODUCT}_common"

  echo "🔁 MODE: SHARED"
  echo "➡️ Discovering groups: grp-${PRODUCT}-*-users"

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

  if [ -z "$GROUPS" ]; then
    echo "❌ No matching groups found"
    exit 1
  fi

  echo "➡️ Applying grants to shared schema: ${SCHEMA_NAME}"

  for GROUP in $GROUPS; do
    echo "   Granting to $GROUP"
    run_sql "GRANT USAGE ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\` TO \`${GROUP}\`"
    run_sql "GRANT SELECT ON ALL TABLES IN SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\` TO \`${GROUP}\`"
  done

  echo "✅ SHARED access applied successfully"
fi

# ===============================
# MODE : DEDICATED
# ===============================
if [ "$MODE" == "DEDICATED" ]; then
  GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"
  SCHEMA_NAME="${PRODUCT}_${CUSTOMER_CODE}"
  WAREHOUSE_NAME="wh-${PRODUCT}-${CUSTOMER_CODE}"

  echo "🔐 MODE: DEDICATED"
  echo "Customer : ${CUSTOMER_CODE}"
  echo "Group    : ${GROUP_NAME}"
  echo "Warehouse: ${WAREHOUSE_NAME}"

  # Create schema
  run_sql "CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\`"

  # Create warehouse
  echo "➡️ Creating SQL Warehouse ${WAREHOUSE_NAME}"
  curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/sql/warehouses" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${WAREHOUSE_NAME}\",
      \"cluster_size\": \"Small\",
      \"auto_stop_mins\": 10,
      \"enable_serverless_compute\": true
    }" > /dev/null

  # Grant warehouse access
  run_sql "GRANT USAGE ON WAREHOUSE \`${WAREHOUSE_NAME}\` TO \`${GROUP_NAME}\`"

  # Grant schema access
  run_sql "GRANT USAGE ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\` TO \`${GROUP_NAME}\`"
  run_sql "GRANT SELECT ON ALL TABLES IN SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_NAME}\` TO \`${GROUP_NAME}\`"

  echo "✅ DEDICATED access applied successfully"
fi

echo "🎉 SCRIPT COMPLETED SUCCESSFULLY"
