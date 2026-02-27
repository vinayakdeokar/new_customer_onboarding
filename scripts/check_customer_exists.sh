#!/bin/bash
set -euo pipefail

CUSTOMER=$1
PRODUCT=$2
ENV=$3

if [ -z "$CUSTOMER" ] || [ -z "$PRODUCT" ] || [ -z "$ENV" ]; then
  echo "Missing arguments"
  exit 1
fi

SCHEMA_NAME="sch-${PRODUCT}-${CUSTOMER_CODE}-bronze-001
WORKSPACE_NAME="${CUSTOMER}-${PRODUCT}-${ENV}"
CONNECTION_NAME="db-vnet-${ENV}-${CUSTOMER}"
CATALOG_NAME="cat-mcr-${ENV}-001"

echo "--------------------------------------------------"
echo "Customer Pre-Check Started"
echo "Customer   : $CUSTOMER"
echo "Product    : $PRODUCT"
echo "Env        : $ENV"
echo "Schema     : $SCHEMA_NAME"
echo "Workspace  : $WORKSPACE_NAME"
echo "Connection : $CONNECTION_NAME"
echo "--------------------------------------------------"

# # --------------------------------------------------
# # Generate Azure AD Token (NO PAT)
# # --------------------------------------------------

# : "${AZURE_CLIENT_ID:?missing}"
# : "${AZURE_CLIENT_SECRET:?missing}"
# : "${AZURE_TENANT_ID:?missing}"
# : "${DATABRICKS_HOST:?missing}"
# : "${DATABRICKS_SQL_WAREHOUSE_ID:?missing}"
# : "${CATALOG_NAME:?missing}"
# : "${FABRIC_CLIENT_ID:?missing}"
# : "${FABRIC_CLIENT_SECRET:?missing}"
# : "${FABRIC_TENANT_ID:?missing}"
# : "${WORKSPACE:?missing}"

echo "Logging into Azure using SPN..."

az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" > /dev/null

echo "Generating Databricks AAD token..."

DB_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

if [ -z "$DB_TOKEN" ]; then
  echo "Failed to generate Databricks token"
  exit 1
fi

echo "Token generated successfully"

# --------------------------------------------------
# Check Databricks Schema
# --------------------------------------------------

echo "Checking Databricks schema..."

RESPONCE=$(curl -s \
  -X POST \
  "$DATABRICKS_HOST/api/2.0/sql/statements/" \
  -H "Authorization: Bearer $DB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"statement\": \"SHOW SCHEMAS IN ${CATALOG_NAME} LIKE '${SCHEMA_NAME}'\",
        \"warehouse_id\": \"${DATABRICKS_SQL_WAREHOUSE_ID}\"
      }" \
  SCHEMA_EXISTS=$(echo "$RESPONCE" | jq -r '.result.data_array | length')
  echo "looking for schema: $SCHEMA_NAME"
  echo "Match count: $SCHEMA_EXISTS"

if [ "$SCHEMA_EXISTS" -gt 0 ]; then
  echo "Databricks schema already exists"
  exit 99
fi

echo "Schema not found"

# --------------------------------------------------
# Check Fabric Workspace
# --------------------------------------------------

echo "Checking Fabric workspace..."

FAB="$WORKSPACE/fabricenv/bin/fab"

# $FAB auth login \
#   -u "$FABRIC_CLIENT_ID" \
#   -p "$FABRIC_CLIENT_SECRET" \
#   --tenant "$FABRIC_TENANT_ID" >/dev/null

# if $FAB workspace list | grep -w "$WORKSPACE_NAME" > /dev/null 2>&1; then
#   echo "Fabric workspace already exists"
#   exit 99
# fi

# echo "Workspace not found"

# # --------------------------------------------------
# #  Check Fabric VNet Connection
# # --------------------------------------------------

# echo "Checking Fabric VNet connection..."

# EXISTING_CONNECTION=$($FAB api connections -A fabric | \
# jq -r '.text.value[]? | select(.displayName=="'"${CONNECTION_NAME}"'") | .id')

# if [ -n "$EXISTING_CONNECTION" ]; then
#   echo "Fabric VNet connection already exists"
#   exit 99
# fi

# echo "Connection not found"

# # --------------------------------------------------
# # Safe to Continue
# # --------------------------------------------------

# echo "--------------------------------------------------"
# echo "Customer does NOT exist – safe to onboard"
# echo "--------------------------------------------------"
