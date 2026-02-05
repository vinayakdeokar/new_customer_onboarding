#!/bin/bash
set -e

SPN_DISPLAY_NAME=$1

if [ -z "$SPN_DISPLAY_NAME" ]; then
  echo "❌ SPN display name not provided"
  exit 1
fi

if [ -z "$DATABRICKS_ADMIN_TOKEN" ] || [ -z "$DATABRICKS_HOST" ]; then
  echo "❌ Databricks admin token or host missing"
  exit 1
fi

if [ -z "$KV_NAME" ]; then
  echo "❌ Azure Key Vault name (KV_NAME) missing"
  exit 1
fi

echo "🔎 Finding Databricks SPN: $SPN_DISPLAY_NAME"

# -------------------------------------------------
# 1️⃣ Get Databricks SPN internal ID
# -------------------------------------------------
SPN_ID=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals?filter=displayName%20eq%20\"$SPN_DISPLAY_NAME\"" \
  | jq -r '.Resources[0].id')

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
  echo "❌ Databricks SPN not found"
  exit 1
fi

echo "✅ Databricks SPN ID resolved"

# -------------------------------------------------
# 2️⃣ Generate Databricks OAuth secret
# -------------------------------------------------
echo "🔐 Generating Databricks OAuth secret..."

SECRET_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  "$DATABRICKS_HOST/api/2.0/oauth2/secrets" \
  -d "{
        \"service_principal_id\": \"$SPN_ID\"
      }")

OAUTH_CLIENT_ID=$(echo "$SECRET_RESPONSE" | jq -r '.client_id')
OAUTH_CLIENT_SECRET=$(echo "$SECRET_RESPONSE" | jq -r '.client_secret')

if [ -z "$OAUTH_CLIENT_SECRET" ] || [ "$OAUTH_CLIENT_SECRET" == "null" ]; then
  echo "❌ OAuth secret generation failed"
  exit 1
fi

echo "✅ OAuth secret generated (one-time)"

# -------------------------------------------------
# 3️⃣ Store secrets in Azure Key Vault
# -------------------------------------------------
KV_CLIENT_ID_SECRET="${SPN_DISPLAY_NAME}-dbx-client-id"
KV_CLIENT_SECRET_SECRET="${SPN_DISPLAY_NAME}-dbx-client-secret"

echo "🔐 Storing secrets in Azure Key Vault: $KV_NAME"

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "$KV_CLIENT_ID_SECRET" \
  --value "$OAUTH_CLIENT_ID" \
  --output none

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "$KV_CLIENT_SECRET_SECRET" \
  --value "$OAUTH_CLIENT_SECRET" \
  --output none

echo "🎉 Secrets stored successfully in Key Vault"
echo "   ➜ $KV_CLIENT_ID_SECRET"
echo "   ➜ $KV_CLIENT_SECRET_SECRET"
