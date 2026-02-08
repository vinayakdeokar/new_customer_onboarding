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
# 0️⃣ SYNC ENTRA GROUP TO WORKSPACE (Add this before Grants)
# -------------------------------
echo "➡️ Ensuring Group '$GROUP_NAME' is synced to workspace..."

# आधी चेक करा ग्रुप आहे का
GROUP_EXISTS=$(curl -s -X GET "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups?filter=displayName+eq+%22$GROUP_NAME%22" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}")

if [[ $(echo "$GROUP_EXISTS" | jq -r '.totalResults') == "0" ]]; then
    echo "🔗 Group not found in workspace. Syncing from Azure Entra ID..."
    # ही कमांड Azure मधील ग्रुपला वर्कस्पेसला 'Attach' करते
    curl -s -X POST "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
      -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"displayName\": \"$GROUP_NAME\", \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"]}" > /dev/null
    echo "✅ Group synced successfully."
else
    echo "✅ Group already synced."
fi

# -------------------------------
# 2️⃣ GRANTS (With Auto-Retry Fix)
# -------------------------------
echo "➡️ Applying grants..."

# --- FIX START: Wait for SQL Warehouse to see the Group ---
echo "⏳ Waiting for Group '$GROUP_NAME' to be visible in SQL Warehouse..."

MAX_RETRIES=20
SLEEP_SECONDS=5
FOUND_GROUP=false

for ((i=1; i<=MAX_RETRIES; i++)); do
  # आपण इथे मुद्दाम run_sql वापरत नाही आहोत कारण ते Error आल्यावर Script बंद करते.
  # त्याऐवजी आपण direct curl वापरून चेक करू.
  
  CHECK_RESPONSE=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
      \"statement\": \"SHOW GROUPS\"
    }")
  
  # रिस्पॉन्समध्ये ग्रुपचे नाव शोधणे
  if echo "$CHECK_RESPONSE" | grep -q "$GROUP_NAME"; then
    echo "✅ Group found in SQL Warehouse! Proceeding..."
    FOUND_GROUP=true
    break
  else
    echo "⚠️ Group not yet visible to SQL Engine. Retrying in $SLEEP_SECONDS seconds... ($i/$MAX_RETRIES)"
    sleep $SLEEP_SECONDS
  fi
done

if [ "$FOUND_GROUP" = false ]; then
  echo "❌ CRITICAL: Group '$GROUP_NAME' sync timed out. SQL Warehouse cannot see it."
  exit 1
fi
# --- FIX END ---

# आता तुझे नॉर्मल GRANTS कमांड्स (हे आता फेल होणार नाहीत)
echo "➡️ Granting permissions..."

run_sql "GRANT USE CATALOG ON CATALOG \`${CATALOG_NAME}\` TO \`${GROUP_NAME}\`"

run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_BRONZE}\` TO \`${GROUP_NAME}\`"
run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_SILVER}\` TO \`${GROUP_NAME}\`"
run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_GOLD}\` TO \`${GROUP_NAME}\`"

echo "------------------------------------------------"
echo "✅ Schemas and grants created successfully"
echo "------------------------------------------------"
