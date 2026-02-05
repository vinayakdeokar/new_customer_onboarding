#!/bin/bash
set -e

# ==============================
# REQUIRED ENV (from Jenkins)
# ==============================
# DATABRICKS_HOST=https://accounts.azuredatabricks.net
# DATABRICKS_ADMIN_TOKEN=<ACCOUNT_ADMIN_PAT>
# DATABRICKS_ACCOUNT_ID=<ACCOUNT_ID>

SPN_DISPLAY_NAME=$1
EXPIRY_DAYS=${2:-365}

if [ -z "$SPN_DISPLAY_NAME" ]; then
  echo "❌ ERROR: SPN display name not provided"
  exit 1
fi

export DATABRICKS_TOKEN="$DATABRICKS_ADMIN_TOKEN"

echo "=========================================="
echo "Creating Databricks OAuth secret"
echo "SPN        : $SPN_DISPLAY_NAME"
echo "Expiry     : $EXPIRY_DAYS days"
echo "Account ID : $DATABRICKS_ACCOUNT_ID"
echo "=========================================="

# ==============================
# 1️⃣ Get Databricks INTERNAL SPN ID (ACCOUNT LEVEL)
# ==============================
SPN_INTERNAL_ID=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/servicePrincipals" \
  | jq -r ".[] | select(.display_name==\"$SPN_DISPLAY_NAME\") | .id")

if [ -z "$SPN_INTERNAL_ID" ] || [ "$SPN_INTERNAL_ID" == "null" ]; then
  echo "❌ ERROR: SPN '$SPN_DISPLAY_NAME' not found in Databricks ACCOUNT"
  exit 1
fi

echo "✅ Databricks SPN internal ID: $SPN_INTERNAL_ID"

# ==============================
# 2️⃣ Create OAuth Secret
# ==============================
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"lifetime_seconds\": $((EXPIRY_DAYS * 24 * 60 * 60)),
        \"comment\": \"jenkins-oauth-secret-$SPN_DISPLAY_NAME\"
      }" \
  "$DATABRICKS_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/servicePrincipals/$SPN_INTERNAL_ID/credentials/secrets")

OAUTH_SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET_VALUE" ]; then
  echo "❌ ERROR: Failed to generate OAuth secret"
  echo "Response: $RESPONSE"
  exit 1
fi

echo "=========================================="
echo "✅ OAuth secret generated SUCCESSFULLY"
echo "⚠️ COPY THIS VALUE NOW (won't be shown again)"
echo "------------------------------------------"
echo "$OAUTH_SECRET_VALUE"
echo "------------------------------------------"
echo "=========================================="
