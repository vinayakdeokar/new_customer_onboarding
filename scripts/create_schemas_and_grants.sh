#!/bin/bash
set -e

# -----------------------------
# INPUTS (from Jenkins params)
# -----------------------------
PRODUCT="${PRODUCT}"
CUSTOMER_CODE="${CUSTOMER_CODE}"

CATALOG_NAME="${CATALOG_NAME}"
WAREHOUSE_ID="${DATABRICKS_SQL_WAREHOUSE_ID}"
HOST="${DATABRICKS_HOST}"
TOKEN="${DATABRICKS_ADMIN_TOKEN}"

# -----------------------------
# DERIVED NAMES
# -----------------------------
BASE_SCHEMA="${PRODUCT}-${CUSTOMER_CODE}"

BRONZE_SCHEMA="${BASE_SCHEMA}_bronze"
SILVER_SCHEMA="${BASE_SCHEMA}_silver"
GOLD_SCHEMA="${BASE_SCHEMA}_gold"

DATA_GROUP="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

BRONZE_FS="abfss://bronz@stcrmmedicareadv.dfs.core.windows.net/${CUSTOMER_CODE}"
EXTERNAL_LOCATION="ext_bronze_${BASE_SCHEMA}"

echo "------------------------------------------------"
echo "Catalog   : $CATALOG_NAME"
echo "Schemas   : $BRONZE_SCHEMA | $SILVER_SCHEMA | $GOLD_SCHEMA"
echo "Group     : $DATA_GROUP"
echo "Bronze FS : $BRONZE_FS"
echo "------------------------------------------------"

# -----------------------------
# SQL STATEMENTS
# -----------------------------
SQL=$(cat <<EOF
-- External location (idempotent)
CREATE EXTERNAL LOCATION IF NOT EXISTS $EXTERNAL_LOCATION
URL '$BRONZE_FS'
WITH (STORAGE CREDENTIAL new_db_test);

GRANT READ FILES, WRITE FILES
ON EXTERNAL LOCATION $EXTERNAL_LOCATION
TO \`$DATA_GROUP\`;

-- Schemas
CREATE SCHEMA IF NOT EXISTS $CATALOG_NAME.$BRONZE_SCHEMA;
CREATE SCHEMA IF NOT EXISTS $CATALOG_NAME.$SILVER_SCHEMA;
CREATE SCHEMA IF NOT EXISTS $CATALOG_NAME.$GOLD_SCHEMA;

-- Catalog access
GRANT USE CATALOG ON CATALOG $CATALOG_NAME TO \`$DATA_GROUP\`;

-- Schema access
GRANT USE SCHEMA, SELECT
ON SCHEMA $CATALOG_NAME.$BRONZE_SCHEMA
TO \`$DATA_GROUP\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA $CATALOG_NAME.$SILVER_SCHEMA
TO \`$DATA_GROUP\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA $CATALOG_NAME.$GOLD_SCHEMA
TO \`$DATA_GROUP\`;
EOF
)

# -----------------------------
# Execute SQL via REST API
# -----------------------------
echo "🚀 Executing SQL in Databricks..."

curl -s -X POST \
  "$HOST/api/2.0/sql/statements" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"statement\": $(jq -Rs . <<< \"$SQL\"),
        \"warehouse_id\": \"$WAREHOUSE_ID\"
      }" >/dev/null

echo "✅ Schemas + Grants created successfully"
