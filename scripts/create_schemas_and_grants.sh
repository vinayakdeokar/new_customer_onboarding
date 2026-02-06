#!/bin/bash
set -e

# --------------------------------------------
# Load context from pre-check
# --------------------------------------------
if [ -f db_env.sh ]; then
  . ./db_env.sh
else
  echo "❌ db_env.sh not found"
  exit 1
fi

: "${CATALOG_NAME:?missing CATALOG_NAME}"
: "${CUSTOMER_CODE:?missing CUSTOMER_CODE}"
: "${DATA_GROUP:?missing DATA_GROUP}"
: "${BRONZE_STORAGE_ROOT:?missing BRONZE_STORAGE_ROOT}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?missing SQL warehouse id}"

echo "------------------------------------------------"
echo "Catalog   : $CATALOG_NAME"
echo "Customer  : $CUSTOMER_CODE"
echo "Group     : $DATA_GROUP"
echo "Bronze FS : $BRONZE_STORAGE_ROOT"
echo "------------------------------------------------"

# --------------------------------------------
# Unity Catalog SQL
# --------------------------------------------
read -r -d '' SQL <<EOF
-- Create schemas
CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${CUSTOMER_CODE}_bronze
MANAGED LOCATION '${BRONZE_STORAGE_ROOT}';

CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${CUSTOMER_CODE}_silver;
CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${CUSTOMER_CODE}_gold;

-- GRANTS : BRONZE
GRANT USE_SCHEMA, CREATE TABLE
ON SCHEMA ${CATALOG_NAME}.${CUSTOMER_CODE}_bronze
TO \`${DATA_GROUP}\`;

-- GRANTS : SILVER
GRANT USE_SCHEMA, CREATE TABLE
ON SCHEMA ${CATALOG_NAME}.${CUSTOMER_CODE}_silver
TO \`${DATA_GROUP}\`;

-- GRANTS : GOLD (consumption layer)
GRANT USE_SCHEMA, CREATE TABLE, SELECT
ON SCHEMA ${CATALOG_NAME}.${CUSTOMER_CODE}_gold
TO \`${DATA_GROUP}\`;
EOF

# --------------------------------------------
# Execute SQL
# --------------------------------------------
echo "🚀 Creating schemas & applying grants..."

databricks sql execute \
  --warehouse-id "$DATABRICKS_SQL_WAREHOUSE_ID" \
  --sql "$SQL"

echo "------------------------------------------------"
echo "✅ Schemas created successfully"
echo "✅ Grants applied to group"
echo "------------------------------------------------"
