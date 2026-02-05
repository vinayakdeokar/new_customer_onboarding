#!/bin/bash
set -e

# ============================================================
# REQUIRED ENV (from Jenkins)
# ------------------------------------------------------------
# PRODUCT                 (e.g. m360)
# CUSTOMER                (e.g. vinayak-002)
# DATABRICKS_HOST          = https://accounts.azuredatabricks.net
# DATABRICKS_TOKEN         = Account Admin PAT
# ACCOUNT_ID               = Databricks Account ID
#
# Also required on agent:
#   az CLI logged in (azure_login.sh already ran)
#   jq installed
# ============================================================

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "============================================================"
echo "Databricks Account SPN & OAuth Secret"
echo "Target SPN : ${SPN_NAME}"
echo "============================================================"

# ------------------------------------------------------------
# 1) Fetch Azure SPN Application (Client) ID dynamically
# ------------------------------------------------------------
CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" -o tsv)

if [ -z "$CLIENT_ID" ]; then
  echo "❌ ERROR: Azure SPN not found: $SPN_NAME"
  exit 1
fi

echo "✅ Azure SPN Client ID: $CLIENT_ID"

# ------------------------------------------------------------
# 2) Check if Account-native SPN exists in Databricks Account
#    (OAuth secrets require ACCOUNT-NATIVE SPN)
# ------------------------------------------------------------
ACCOUNT_SPN_ID=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals" \
  | jq -r ".[] | select(.application_id==\"$CLIENT_ID\") | .id")

# ------------------------------------------------------------
# 3) If not exists → create Account-native SPN (idempotent)
# ------------------------------------------------------------
if [ -z "$ACCOUNT_SPN_ID" ]; then
  echo "ℹ️ Account-native SPN not found. Creating..."

  CREATE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $DATABRICKS_TOKEN" \
    -H "Content-Type: application/json" \
    "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals" \
    -d "{
      \"applicationId\": \"$CLIENT_ID\",
      \"displayName\": \"$SPN_NAME\"
    }")
  
  ACCOUNT_SPN_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')

  if [ -z "$ACCOUNT_SPN_ID" ] || [ "$ACCOUNT_SPN_ID" == "null" ]; then
    echo "❌ ERROR: Failed to create account-native SPN"
    echo "$CREATE_RESPONSE"
    exit 1
  fi

  echo "✅ Account-native SPN created"
else
  echo "✅ Account-native SPN already exists"
fi

echo "Account SPN Internal ID: $ACCOUNT_SPN_ID"

# ------------------------------------------------------------
# 4) Create OAuth Secret for Account-native SPN
# ------------------------------------------------------------
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$ACCOUNT_SPN_ID/credentials/secrets" \
  -d "{
        \"lifetime_seconds\": 31536000,
        \"comment\": \"auto-oauth-${SPN_NAME}\"
      }")

OAUTH_SECRET=$(echo "$RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET" ]; then
  echo "❌ ERROR: OAuth secret creation failed"
  echo "$RESPONSE"
  exit 1
fi

echo "============================================================"
echo "✅ OAUTH SECRET CREATED (copy & store securely)"
echo "------------------------------------------------------------"
echo "$OAUTH_SECRET"
echo "------------------------------------------------------------"
echo "============================================================"

# Optional: persist for next steps (recommend storing in Key Vault instead)
# echo "export FINAL_OAUTH_SECRET=$OAUTH_SECRET" >> db_env.sh
