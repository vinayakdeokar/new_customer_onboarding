#!/bin/bash
set -e

SPN_DISPLAY_NAME=$1

if [ -z "$SPN_DISPLAY_NAME" ]; then
  echo "❌ SPN display name missing"
  exit 1
fi

if [ -z "$KV_NAME" ]; then
  echo "❌ KV_NAME missing"
  exit 1
fi

echo "🔐 Step 1: Verify Databricks CLI login"
databricks clusters list > /dev/null
echo "✅ Databricks CLI login OK"

echo "🔎 Step 2: Resolve Databricks SPN ID (robust)"

RAW_JSON=$(databricks service-principals list --output json)

SPN_ID=$(echo "$RAW_JSON" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if type=="array" then
    .[] | select(.display_name==$NAME) | .id
  else
    .service_principals[] | select(.display_name==$NAME) | .id
  end
')

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
  echo "❌ SPN not found in Databricks: $SPN_DISPLAY_NAME"
  echo "Available SPNs:"
  echo "$RAW_JSON" | jq -r '
    if type=="array" then .[].display_name
    else .service_principals[].display_name end
  '
  exit 1
fi

echo "✅ SPN ID resolved: $SPN_ID"

echo "🔐 Step 3: Generate OAuth secret using Databricks CLI"

SECRET_JSON=$(databricks service-principals secrets create "$SPN_ID" --output json)

OAUTH_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.client_id')
OAUTH_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.client_secret')

if [ -z "$OAUTH_CLIENT_SECRET" ] || [ "$OAUTH_CLIENT_SECRET" == "null" ]; then
  echo "❌ OAuth secret generation failed"
  exit 1
fi

echo "✅ OAuth secret generated (one-time)"

echo "🔐 Step 4: Store secrets in Azure Key Vault: $KV_NAME"

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${SPN_DISPLAY_NAME}-dbx-client-id" \
  --value "$OAUTH_CLIENT_ID" \
  --output none

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${SPN_DISPLAY_NAME}-dbx-client-secret" \
  --value "$OAUTH_CLIENT_SECRET" \
  --output none

echo "🎉 DONE: OAuth secret generated & stored in Key Vault"
