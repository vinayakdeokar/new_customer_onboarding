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
# 5A. Fetch Client ID (Application ID) from Databricks
# --------------------------------------------------

echo "🔎 Fetching Client ID (Application ID) from Databricks..."

SPN_RESPONSE=$(curl -sf -X GET \
  -H "Authorization: Bearer $DB_TOKEN" \
  "$ACCOUNTS_BASE_URL/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID")

CLIENT_ID=$(echo "$SPN_RESPONSE" | jq -r '.applicationId // empty')

if [ -z "$CLIENT_ID" ]; then
  echo "❌ Failed to fetch Client ID from Databricks"
  echo "Response: $SPN_RESPONSE"
  exit 1
fi

echo "✅ Client ID fetched"
echo "   Client ID: $CLIENT_ID"


# --------------------------------------------------
# 6. Store OAuth secret in Azure Key Vault (ROTATION)
# --------------------------------------------------

: "${KV_NAME:?missing Key Vault name}"

SECRET_NAME="${TARGET_SPN_DISPLAY_NAME}-oauth-secret"

echo "🔐 Rotating secret in Azure Key Vault"
echo "   Vault : $KV_NAME"
echo "   Name  : $SECRET_NAME"

# --- A. Create NEW secret version (enabled by default)
NEW_VERSION_ID=$(az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "$SECRET_NAME" \
  --value "$OAUTH_SECRET_VALUE" \
  --query "id" -o tsv)

echo "✅ New secret version created"
echo "   New Version ID: $NEW_VERSION_ID"

# --- B. Disable ALL older enabled versions
OLD_VERSIONS=$(az keyvault secret list-versions \
  --vault-name "$KV_NAME" \
  --name "$SECRET_NAME" \
  --query "[?attributes.enabled==\`true\` && id!='$NEW_VERSION_ID'].id" \
  -o tsv)

if [ -n "$OLD_VERSIONS" ]; then
  echo "🛑 Disabling old secret versions..."
  for VERSION_ID in $OLD_VERSIONS; do
    az keyvault secret set-attributes \
      --id "$VERSION_ID" \
      --enabled false \
      --output none
    echo "   Disabled: ...${VERSION_ID: -8}"
  done
else
  echo "ℹ️ No old versions found to disable"
fi

echo "-------------------------------------------------------"
echo "✅ Key Vault rotation complete"
echo "   Only latest secret version is ENABLED"
echo "-------------------------------------------------------"

# --------------------------------------------------
# 7. Store Client ID in Azure Key Vault (ROTATION)
# --------------------------------------------------

CLIENT_ID_SECRET_NAME="${TARGET_SPN_DISPLAY_NAME}-client-id"

echo "🔐 Rotating Client ID in Azure Key Vault"
echo "   Vault : $KV_NAME"
echo "   Name  : $CLIENT_ID_SECRET_NAME"

NEW_CLIENT_VERSION_ID=$(az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "$CLIENT_ID_SECRET_NAME" \
  --value "$CLIENT_ID" \
  --query "id" -o tsv)

echo "✅ New Client ID version created"
echo "   New Version ID: $NEW_CLIENT_VERSION_ID"

OLD_CLIENT_VERSIONS=$(az keyvault secret list-versions \
  --vault-name "$KV_NAME" \
  --name "$CLIENT_ID_SECRET_NAME" \
  --query "[?attributes.enabled==\`true\` && id!='$NEW_CLIENT_VERSION_ID'].id" \
  -o tsv)

if [ -n "$OLD_CLIENT_VERSIONS" ]; then
  echo "🛑 Disabling old Client ID versions..."
  for VERSION_ID in $OLD_CLIENT_VERSIONS; do
    az keyvault secret set-attributes \
      --id "$VERSION_ID" \
      --enabled false \
      --output none
    echo "   Disabled: ...${VERSION_ID: -8}"
  done
else
  echo "ℹ️ No old Client ID versions found to disable"
fi

echo "-------------------------------------------------------"
echo "✅ Client ID stored successfully"
echo "-------------------------------------------------------"


