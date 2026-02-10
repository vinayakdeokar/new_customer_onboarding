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
#: "${STORAGE_BRONZE_ROOT:?STORAGE_BRONZE_ROOT missing}"
: "${STORAGE_BRONZE_CONTAINER:?STORAGE_BRONZE_CONTAINER missing}"

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
BRONZE_SCHEMA="${PRODUCT}_${CUSTOMER_CODE}_bronze"
BRONZE_PATH="${STORAGE_BRONZE_CONTAINER}/${CUSTOMER_CODE}"

echo "🔐 MODE      : ${MODE}"
echo "Customer    : ${CUSTOMER_CODE}"
echo "Group       : ${GROUP_NAME}"
echo "Catalog     : ${CATALOG_NAME}"
#echo "Bronze Root : ${STORAGE_BRONZE_ROOT}"
echo "Bronze Path : ${BRONZE_PATH}"


run_sql_with_retry () {
  local SQL="$1"
  local MAX_RETRIES=10
  local COUNT=1

  while [ $COUNT -le $MAX_RETRIES ]; do
    echo "⏳ Attempt $COUNT/$MAX_RETRIES for UC principal..."

    set +e
    run_sql "$SQL"
    RESULT=$?
    set -e

    if [ $RESULT -eq 0 ]; then
      echo "✅ UC principal recognised"
      return 0
    fi

    echo "⚠️ UC principal अजून तयार नाही, 30s थांबतोय..."
    sleep 30
    COUNT=$((COUNT+1))
  done

  echo "❌ ERROR: UC principal $GROUP_NAME अजूनही ओळखला गेला नाही"
  exit 1
}


# आता तुझी पहिली GRANT कमांड या नवीन फंक्शनने रन कर
run_sql_with_retry "
GRANT USE CATALOG
ON CATALOG \`${CATALOG_NAME}\`
TO \`${GROUP_NAME}\`
"

# ------------------------------------------------
# पुढचा सर्व 'run_sql' चा कोड आहे तसाच राहू दे...
# ------------------------------------------------

# echo "🔥 Pre-warming Unity Catalog principal (first GRANT)..."

# run_sql "
# GRANT USE CATALOG
# ON CATALOG \`${CATALOG_NAME}\`
# TO \`${GROUP_NAME}\`
# "

GRANT READ FILES, WRITE FILES
ON EXTERNAL LOCATION ext_bronze_mcr
TO `${GROUP_NAME}`

# ------------------------------------------------
# 1️⃣ BRONZE SCHEMA (ATTACH TO EXISTING EXTERNAL LOCATION)
# ------------------------------------------------
run_sql "
CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
LOCATION '${BRONZE_PATH}'
"

run_sql "
GRANT USAGE, SELECT
ON SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
TO \`${GROUP_NAME}\`
"

# ------------------------------------------------
# 2️⃣ SILVER & GOLD SCHEMAS (DEFAULT MANAGED)
# ------------------------------------------------
for LAYER in silver gold; do
  SCHEMA_NAME="${PRODUCT}_${CUSTOMER_CODE}_${LAYER}"

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
