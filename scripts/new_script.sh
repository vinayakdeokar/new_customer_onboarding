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
: "${STORAGE_BRONZE_ROOT:?STORAGE_BRONZE_ROOT missing}"

GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"
BRONZE_SCHEMA="${PRODUCT}_${CUSTOMER_CODE}_bronze"

echo "🔐 MODE      : ${MODE}"
echo "Customer    : ${CUSTOMER_CODE}"
echo "Group       : ${GROUP_NAME}"
echo "Catalog     : ${CATALOG_NAME}"
echo "Bronze Root : ${STORAGE_BRONZE_ROOT}"

# ===============================
# HELPER: RUN SQL
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
# 1️⃣ ENSURE GROUP EXISTS IN WORKSPACE
# ===============================
echo "🔍 Checking group in workspace..."

GROUP_ID=$(curl -s -X GET \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups?filter=displayName eq \"${GROUP_NAME}\"" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  | jq -r '.Resources[0].id // empty')

if [ -z "$GROUP_ID" ]; then
  echo "➡️ Group not found. Creating in workspace..."

  GROUP_ID=$(curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"displayName\": \"${GROUP_NAME}\"
    }" | jq -r '.id')

  echo "✅ Group created with ID: ${GROUP_ID}"
else
  echo "✅ Group already exists (ID: ${GROUP_ID})"
fi

# ===============================
# 2️⃣ ADD SQL WAREHOUSE ENTITLEMENT
# ===============================
echo "🔑 Ensuring SQL Warehouse entitlement..."

curl -s -X PATCH \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups/${GROUP_ID}" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "schemas":["urn:ietf:params:scim:schemas:core:2.0:Group"],
    "entitlements":[{"value":"databricks-sql-access"}]
  }' >/dev/null

echo "✅ SQL entitlement ensured"

# ===============================
# 3️⃣ BRONZE SCHEMA (EXTERNAL LOCATION)
# ===============================
run_sql "
CREATE SCHEMA IF NOT EXISTS \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
MANAGED LOCATION '${STORAGE_BRONZE_ROOT}'
"

run_sql "
GRANT USAGE, SELECT
ON SCHEMA \`${CATALOG_NAME}\`.\`${BRONZE_SCHEMA}\`
TO \`${GROUP_NAME}\`
"

# ===============================
# 4️⃣ SILVER & GOLD SCHEMAS
# ===============================
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

# ===============================
# 5️⃣ CATALOG ACCESS
# ===============================
run_sql "
GRANT USAGE
ON CATALOG \`${CATALOG_NAME}\`
TO \`${GROUP_NAME}\`
"

echo "✅ AUTOMATION COMPLETED SUCCESSFULLY 🎉"
