#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER=$2

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "Adding SPN to Databricks workspace: $SPN_NAME"


CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" -o tsv)

if [ -z "$CLIENT_ID" ]; then
  echo "ERROR: Azure SPN $SPN_NAME not found in Entra ID"
  exit 1
fi

echo "Found Azure SPN Client ID: $CLIENT_ID"


if databricks service-principals list | grep -q "$CLIENT_ID"; then
  echo "SPN already exists in Databricks workspace"
  exit 0
fi


echo "Creating SPN in Databricks workspace"
databricks service-principals create \
  --application-id "$CLIENT_ID" \
  --display-name "$SPN_NAME"

echo "SPN $SPN_NAME successfully added to Databricks workspace"
