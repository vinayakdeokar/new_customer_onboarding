#!/bin/bash
set -e
source db_env.sh

EXT_LOC="ext_bronze_${CUSTOMER//-/_}"
BRONZE_SCHEMA="${CUSTOMER//-/_}_bronze"
SILVER_SCHEMA="${CUSTOMER//-/_}_silver"
GOLD_SCHEMA="${CUSTOMER//-/_}_gold"

SQL=$(cat <<EOF
CREATE EXTERNAL LOCATION IF NOT EXISTS ${EXT_LOC}
URL '${STORAGE_PATH}'
WITH (STORAGE CREDENTIAL new_db_test);

GRANT READ FILES, WRITE FILES
ON EXTERNAL LOCATION ${EXT_LOC}
TO \`${GROUP_NAME}\`;

CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${BRONZE_SCHEMA}
MANAGED LOCATION '${STORAGE_PATH}';

CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${SILVER_SCHEMA};
CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${GOLD_SCHEMA};

GRANT USE CATALOG ON CATALOG ${CATALOG_NAME}
TO \`${GROUP_NAME}\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA ${CATALOG_NAME}.${BRONZE_SCHEMA}
TO \`${GROUP_NAME}\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA ${CATALOG_NAME}.${SILVER_SCHEMA}
TO \`${GROUP_NAME}\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA ${CATALOG_NAME}.${GOLD_SCHEMA}
TO \`${GROUP_NAME}\`;
EOF
)

echo "🚀 Submitting SQL to Databricks..."

# Encode SQL safely
SQL_B64=$(echo "$SQL" | base64 | tr -d '\n')

RESPONSE=$(curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/sql/statements" \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"statement\": \"$(echo $SQL_B64 | base64 -d | sed 's/\"/\\\\\"/g')\",
    \"warehouse_id\": \"$DATABRICKS_SQL_WAREHOUSE_ID\"
  }")

# Extract statement_id WITHOUT jq
STATEMENT_ID=$(echo "$RESPONSE" | sed -n 's/.*"statement_id":"\\([^"]*\\)".*/\\1/p')

if [ -z "$STATEMENT_ID" ]; then
  echo "❌ Failed to submit SQL"
  echo "Response:"
  echo "$RESPONSE"
  exit 1
fi

echo "🕒 Statement ID: $STATEMENT_ID"
echo "⏳ Waiting for execution to complete..."

# ---- Polling loop ----
while true; do
  STATUS_RESP=$(curl -s \
    "$DATABRICKS_HOST/api/2.0/sql/statements/$STATEMENT_ID" \
    -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN")

  STATE=$(echo "$STATUS_RESP" | sed -n 's/.*"state":"\\([^"]*\\)".*/\\1/p')

  echo "   ➜ Status: $STATE"

  if [ "$STATE" = "SUCCEEDED" ]; then
    echo "✅ Schemas + external location + grants created successfully"
    break
  fi

  if [ "$STATE" = "FAILED" ]; then
    echo "❌ SQL execution failed"
    echo "$STATUS_RESP"
    exit 1
  fi

  sleep 3
done
