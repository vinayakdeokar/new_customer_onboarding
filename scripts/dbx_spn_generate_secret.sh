#!/bin/bash
set -e

# --------------------------------------------------
# 1. Load env
# --------------------------------------------------
if [ -f db_env.sh ]; then
  . ./db_env.sh
else
  echo "ERROR: db_env.sh not found"
  exit 1
fi

: "${TARGET_SPN_DISPLAY_NAME:?missing}"
: "${DATABRICKS_INTERNAL_ID:?missing}"
: "${DATABRICKS_ACCOUNT_ID:?missing}"

ACCOUNTS_BASE_URL="https://accounts.azuredatabricks.net"

echo "-------------------------------------------------------"
echo "Target SPN        : $TARGET_SPN_DISPLAY_NAME"
echo "Internal SPN ID   : $DATABRICKS_INTERNAL_ID"
echo "Account ID        : $DATABRICKS_ACCOUNT_ID"
echo "-------------------------------------------------------"

# --------------------------------------------------
# 2. Get TEMP Databricks Account token (IMPORTANT)
# --------------------------------------------------
echo "🔐 Generating temporary Databricks Account token via Azure AD..."

DB_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

if [ -z "$DB_TOKEN" ]; then
  echo "❌ Failed to obtain Databricks account token"
  exit 1
fi

echo "✅ Temporary account token obtained"

# --------------------------------------------------
# 3. Create OAuth secret (Account-level API)
# --------------------------------------------------
echo "🔐 Creating OAuth secret at Databricks Account level..."

RESPONSE=$(curl -sf -X POST \
  -H "Authorization: Bearer $DB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"lifetime_seconds\": 31536000,
        \"comment\": \"Rotated via Jenkins for $TARGET_SPN_DISPLAY_NAME\"
      }" \
  "$ACCOUNTS_BASE_URL/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets")

OAUTH_SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // empty')

# --------------------------------------------------
# 4. Validation (Gatekeeper)
# --------------------------------------------------
if [ -z "$OAUTH_SECRET_VALUE" ]; then
  echo "❌ Databricks did not return a valid secret"
  echo "Response: $RESPONSE"
  exit 1
fi

# --------------------------------------------------
# 5. Persist for next stages
# --------------------------------------------------
echo "export FINAL_OAUTH_SECRET=$OAUTH_SECRET_VALUE" >> db_env.sh

echo "-------------------------------------------------------"
echo "✅ SUCCESS: OAuth secret generated using TEMP token"
echo "-------------------------------------------------------"

# --------------------------------------------------
# 6. Store OAuth secret securely in Azure Key Vault
# --------------------------------------------------

: "${KV_NAME:?missing Key Vault name}"

SECRET_NAME="${TARGET_SPN_DISPLAY_NAME}-oauth-secret"

echo "🔐 Storing OAuth secret in Azure Key Vault"
echo "   Vault : $KV_NAME"
echo "   Name  : $SECRET_NAME"

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "$SECRET_NAME" \
  --value "$OAUTH_SECRET_VALUE" \
  --output none

echo "✅ OAuth secret stored securely in Key Vault"

