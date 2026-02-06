#!/usr/bin/env bash
set -euo pipefail

# ===== REQUIRED ENV =====
: "${PRODUCT:?}"
: "${CUSTOMER_CODE:?}"
: "${CATALOG_NAME:?}"
: "${DATABRICKS_HOST:?}"
: "${DATABRICKS_ADMIN_TOKEN:?}"
: "${DATABRICKS_SQL_WAREHOUSE_ID:?}"

BRONZE="${PRODUCT}-${CUSTOMER_CODE}_bronze"
SILVER="${PRODUCT}-${CUSTOMER_CODE}_silver"
GOLD="${PRODUCT}-${CUSTOMER_CODE}_gold"

echo "------------------------------------------------"
echo "Catalog : ${CATALOG_NAME}"
echo "Schemas : ${BRONZE} | ${SILVER} | ${GOLD}"
echo "------------------------------------------------"

SQL=$(cat <<EOF
USE CATALOG \`${CATALOG_NAME}\`;

-- BRONZE
CREATE SCHEMA IF NOT EXISTS \`${BRONZE}\`;

-- SILVER
CREATE SCHEMA IF NOT EXISTS \`${SILVER}\`;
