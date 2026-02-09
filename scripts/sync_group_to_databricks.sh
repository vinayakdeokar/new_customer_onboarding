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

# ग्रुपला SQL Warehouse वापरण्याची परवानगी (Entitlement) देणे
echo "➡️ Adding SQL Warehouse entitlement to group..."
GROUP_ID=$(curl -s -X GET "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups?filter=displayName+eq+%22$GROUP_NAME%22" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" | jq -r '.Resources[0].id')

curl -s -X PATCH "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups/$GROUP_ID" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
    "Operations": [
      {
        "op": "add",
        "path": "entitlements",
        "value": [
          {"value": "databricks-sql-access"}
        ]
      }
    ]
  }'
echo "✅ Entitlement added."
sleep 5
# -------------------------------
# 2️⃣ GRANTS (Dynamic Principal Discovery Fix)
# -------------------------------
echo "➡️ Discovering Exact Principal Name from SQL Engine..."

# SQL Warehouse कडून ग्रुपची लिस्ट मागवून आपल्या ग्रुपचे 'Exact' नाव शोधणे
# यामुळे Case Sensitivity (Capital/Small) चा प्रॉब्लेम कायमचा सुटतो.
EXACT_SQL_GROUP=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"warehouse_id\": \"$DATABRICKS_SQL_WAREHOUSE_ID\", \"statement\": \"SHOW GROUPS\"}" \
  | jq -r '.result.data_array[][]' | grep -i "^${GROUP_NAME}$" | head -n 1)

if [ -z "$EXACT_SQL_GROUP" ] || [ "$EXACT_SQL_GROUP" == "null" ]; then
    echo "❌ ERROR: Group '$GROUP_NAME' SQL Warehouse ला अजिबात दिसत नाहीये."
    echo "कृपया Azure Portal मध्ये ग्रुपचे स्पेलिंग नीट तपासा."
    exit 1
fi

echo "➡️ Applying grants using discovered name..."

# 1️⃣ USE_CATALOG
run_sql "GRANT USAGE ON CATALOG \`${CATALOG_NAME}\` TO \`${EXACT_SQL_GROUP}\`"

# 2️⃣ USE_SCHEMA + SELECT
run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_BRONZE}\` TO \`${EXACT_SQL_GROUP}\`"
run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_SILVER}\` TO \`${EXACT_SQL_GROUP}\`"
run_sql "GRANT USAGE, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_GOLD}\` TO \`${EXACT_SQL_GROUP}\`"

echo "✅ All grants applied successfully."
