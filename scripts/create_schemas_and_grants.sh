#!/bin/bash
set -e

# -------------------------------
# REQUIRED ENV VARIABLES (Jenkins)
# -------------------------------
: "${PRODUCT:?PRODUCT missing}"
: "${CUSTOMER_CODE:?CUSTOMER_CODE missing}"
: "${CATALOG_NAME:?CATALOG_NAME missing}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST missing}"
: "${DATABRICKS_ADMIN_TOKEN:?DATABRICKS_ADMIN_TOKEN missing}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?DATABRICKS_SQL_WAREHOUSE_ID missing}"

# -------------------------------
# DERIVED VALUES
# -------------------------------
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

SCHEMA_BRONZE="${PRODUCT}-${CUSTOMER_CODE}_bronze"
SCHEMA_SILVER="${PRODUCT}-${CUSTOMER_CODE}_silver"
SCHEMA_GOLD="${PRODUCT}-${CUSTOMER_CODE}_gold"

# -------------------------------
# LOG HEADER
# -------------------------------
echo "------------------------------------------------"
echo "Catalog   : ${CATALOG_NAME}"
echo "Schemas   : ${SCHEMA_BRONZE} | ${SCHEMA_SILVER} | ${SCHEMA_GOLD}"
echo "Group     : ${GROUP_NAME}"
echo "------------------------------------------------"

# -------------------------------
# FUNCTION: EXECUTE SQL SAFELY
# -------------------------------
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

# -------------------------------
# 1️⃣ CREATE SCHEMAS
# -------------------------------
echo "➡️ Creating schemas..."

run_sql "CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_BRONZE}\`"
echo "Created in Bronze"
run_sql "CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_SILVER}\`"
run_sql "CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_GOLD}\`"

# -------------------------------
# 2️⃣ GRANTS
# -------------------------------
echo "➡️ Applying grants..."

run_sql "GRANT USE CATALOG ON CATALOG \`${CATALOG_NAME}\` TO \`${GROUP_NAME}\`"

run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_BRONZE}\` TO \`${GROUP_NAME}\`"
run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_SILVER}\` TO \`${GROUP_NAME}\`"
run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_GOLD}\` TO \`${GROUP_NAME}\`"

echo "------------------------------------------------"
echo "✅ Schemas and grants created successfully"
echo "------------------------------------------------"
