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
echo "Catalog : ${CATALOG_NAME}"
echo "Schemas : ${SCHEMA_BRONZE} | ${SCHEMA_SILVER} | ${SCHEMA_GOLD}"
echo "Group   : ${GROUP_NAME}"
echo "------------------------------------------------"

# -------------------------------
# FUNCTION: EXECUTE SQL
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
run_sql "CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_SILVER}\`"
run_sql "CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${SCHEMA_GOLD}\`"

echo "✅ Schemas created."

# -------------------------------
# 2️⃣ VERIFY GROUP EXISTS IN SQL
# -------------------------------
echo "➡️ Verifying group exists in SQL engine..."

GROUP_FOUND=$(curl -s -X POST \
  "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
    \"statement\": \"SHOW GROUPS\"
  }" | jq -r '.result.data_array[][]' | grep -i "^${GROUP_NAME}$" || true)

if [ -z "$GROUP_FOUND" ]; then
  echo "❌ ERROR: Group '${GROUP_NAME}' SQL मध्ये दिसत नाही."
  echo "👉 Azure Entra ID group check कर / 1-2 minutes wait कर."
  exit 1
fi

echo "✅ Group visible in SQL: ${GROUP_FOUND}"

# -------------------------------
# 3️⃣ APPLY GRANTS
# -------------------------------
echo "➡️ Applying grants..."

run_sql "GRANT USAGE ON CATALOG \`${CATALOG_NAME}\` TO \`${GROUP_FOUND}\`"

run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_BRONZE}\` TO \`${GROUP_FOUND}\`"
run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_SILVER}\` TO \`${GROUP_FOUND}\`"
run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_GOLD}\` TO \`${GROUP_FOUND}\`"

echo "🎉 All schemas created and grants applied successfully."
