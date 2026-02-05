#!/bin/bash
set -e

[ -f db_env.sh ] && . db_env.sh

if [ -z "$DATABRICKS_INTERNAL_ID" ]; then
  echo "❌ ERROR: DATABRICKS_INTERNAL_ID not set"
  exit 1
fi

EXPIRY_DAYS=${1:-365}
LIFETIME_SECONDS=$((EXPIRY_DAYS * 24 * 60 * 60))

echo "=========================================="
echo "Creating Databricks OAuth Secret"
echo "SPN        : $TARGET_SPN_DISPLAY_NAME"
echo "InternalID : $DATABRICKS_INTERNAL_ID"
echo "Expiry     : $EXPIRY_DAYS days"
echo "=========================================="

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets" \
  -d "{
        \"lifetime_seconds\": $LIFETIME_SECONDS,
        \"comment\": \"auto-oauth-secret-$TARGET_SPN_DISPLAY_NAME\"
      }")

OAUTH_SECRET=$(echo "$RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET" ]; then
  echo "❌ ERROR: OAuth secret generation failed"
  echo "Response: $RESPONSE"
  exit 1
fi

echo "=========================================="
echo "✅ OAuth secret GENERATED (copy now)"
echo "------------------------------------------"
echo "$OAUTH_SECRET"
echo "------------------------------------------"
echo "=========================================="

echo "export FINAL_OAUTH_SECRET=$OAUTH_SECRET" >> db_env.sh
