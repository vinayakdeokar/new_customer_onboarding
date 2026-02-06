#!/bin/bash
set -e

# ---- INPUT FROM ENV ----
CATALOG_NAME="medicareadv"
CUSTOMER="vinayak-002"
GROUP="grp-m360-vinayak-002-users"

STORAGE_ACCOUNT="stcrmmedicareadv"
CONTAINER="bronz"

EXT_LOC_NAME="ext_bronze_${CUSTOMER//-/_}"
BRONZE_PATH="abfss://${CONTAINER}@${STORAGE_ACCOUNT}.dfs.core.windows.net/${CUSTOMER}"

echo "------------------------------------------------"
echo "Catalog   : $CATALOG_NAME"
echo "Customer  : $CUSTOMER"
echo "Group     : $GROUP"
echo "Bronze FS : $BRONZE_PATH"
echo "------------------------------------------------"

# ---------- SQL ----------
SQL=$(cat <<EOF
-- 1. External location
CREATE EXTERNAL LOCATION IF NOT EXISTS ${EXT_LOC_NAME}
URL '${BRONZE_PATH}'
WITH (STORAGE CREDENTIAL new_db_test);

GRANT READ FILES, WRITE FILES
ON EXTERNAL LOCATION ${EXT_LOC_NAME}
TO \`${GROUP}\`;

-- 2. Schemas
CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${CUSTOMER//-/_}_bronze
MANAGED LOCATION '${BRONZE_PATH}';

CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${CUSTOMER//-/_}_silver;
CREATE SCHEMA IF NOT EXISTS ${CATALOG_NAME}.${CUSTOMER//-/_}_gold;

-- 3. Grants
GRANT USE CATALOG ON CATALOG ${CATALOG_NAME} TO \`${GROUP}\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA ${CATALOG_NAME}.${CUSTOMER//-/_}_bronze
TO \`${GROUP}\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA ${CATALOG_NAME}.${CUSTOMER//-/_}_silver
TO \`${GROUP}\`;

GRANT USE SCHEMA, SELECT
ON SCHEMA ${CATALOG_NAME}.${CUSTOMER//-/_}_gold
TO \`${GROUP}\`;
EOF
)

echo "$SQL" > /tmp/schema.sql

databricks sql warehouses execute \
  --warehouse-id "$DATABRICKS_SQL_WAREHOUSE_ID" \
  --file /tmp/schema.sql

echo "✅ Schemas & grants created successfully"
