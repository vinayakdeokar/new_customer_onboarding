#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER=$2

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "Adding SPN to Databricks workspace: $SPN_NAME"

# 1. Get Azure SPN clientId (appId)
CLIENT_ID=$(az ad sp show \
  --id "$SPN_NAME" \
  --query appId -o tsv)

echo "Client ID: $CLIENT_ID"

# 2. Get Databricks access token using Azure login (Jenkins SPN)
DATABRICKS_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

# 3. Add SPN to Databricks workspace via SCIM API
curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/ServicePrincipals" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"applicationId\": \"${CLIENT_ID}\",
    \"displayName\": \"${SPN_NAME}\"
  }"

echo ""
echo "SPN ${SPN_NAME} added to Databricks workspace (or already exists)."
