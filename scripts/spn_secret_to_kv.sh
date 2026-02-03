#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER_CODE=$2

SPN_NAME="sp-${PRODUCT}-${CUSTOMER_CODE}"
SECRET_NAME="${SPN_NAME}-secret"

echo "Validating SPN: $SPN_NAME"

APP_ID=$(az ad sp list --display-name "$SPN_NAME" --query "[0].appId" -o tsv)

if [ -z "$APP_ID" ]; then
  echo "ERROR: SPN $SPN_NAME not found"
  exit 1
fi

echo "Checking if secret already exists in Key Vault"

if az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET_NAME" >/dev/null 2>&1; then
  echo "Secret already exists in Key Vault"
  exit 0
fi

echo "Generating new SPN secret"
SECRET=$(az ad app credential reset \
  --id "$APP_ID" \
  --query password -o tsv)

echo "Storing secret in Key Vault"
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "$SECRET_NAME" \
  --value "$SECRET" > /dev/null

echo "SPN secret stored successfully"

