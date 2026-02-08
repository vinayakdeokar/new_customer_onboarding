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
# 2️⃣ GRANTS (Ultimate Retry Logic)
# -------------------------------
echo "➡️ Starting Grant Process with Deep Retry..."

# १. पहिल्यांदा CATALOG वर एक्सेस देण्याचा प्रयत्न (हा यशस्वी झाला की बाकीचे होतातच)
MAX_RETRIES=15
SLEEP_SECONDS=10
SUCCESS=false

for ((i=1; i<=MAX_RETRIES; i++)); do
  echo "📡 Attempting GRANT on Catalog (Try $i/$MAX_RETRIES)..."
  
  # आपण मुद्दाम run_sql ऐवजी थेट curl वापरून चेक करतोय जेणेकरून exit 1 होणार नाही
  GRANT_RES=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/sql/statements/" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\",
      \"statement\": \"GRANT USE CATALOG ON CATALOG \`${CATALOG_NAME}\` TO \`${GROUP_NAME}\`\"
    }")

  STATE=$(echo "$GRANT_RES" | jq -r '.status.state // empty')
  ERR_MSG=$(echo "$GRANT_RES" | jq -r '.status.error.message // empty')

  if [ "$STATE" == "SUCCEEDED" ]; then
    echo "✅ SUCCESS: Catalog grant applied!"
    SUCCESS=true
    break
  elif [[ "$ERR_MSG" == *"PRINCIPAL_DOES_NOT_EXIST"* ]]; then
    echo "⚠️ Identity not yet ready in Unity Catalog. Retrying in $SLEEP_SECONDS seconds..."
    sleep $SLEEP_SECONDS
  else
    echo "❌ Unexpected SQL Error: $ERR_MSG"
    exit 1
  fi
done

if [ "$SUCCESS" = false ]; then
  echo "❌ CRITICAL: Even after retries, Unity Catalog cannot see '$GROUP_NAME'."
  exit 1
fi

# जर पहिली कमांड यशस्वी झाली, तर बाकीच्या कमांड्स आता चालतीलच
echo "➡️ Applying Schema Grants..."
run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_BRONZE}\` TO \`${GROUP_NAME}\`"
run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_SILVER}\` TO \`${GROUP_NAME}\`"
run_sql "GRANT USE SCHEMA, SELECT ON SCHEMA \`${CATALOG_NAME}\`.\`${SCHEMA_GOLD}\` TO \`${GROUP_NAME}\`"

echo "------------------------------------------------"
echo "🎉 FINALLY! Schemas and grants are done."
echo "------------------------------------------------"
