#!/bin/bash
set -e

export DATABRICKS_HOST
export DATABRICKS_TOKEN="${DATABRICKS_ADMIN_TOKEN}"

SPN_NAME=$1
EXPIRY_DAYS=${2:-90}

echo "=========================================="
echo "Creating Databricks OAuth secret"
echo "SPN: $SPN_NAME"
echo "Expiry: $EXPIRY_DAYS days"
echo "=========================================="

# 1️⃣ Get Databricks SPN ID
SPN_ID=$(databricks service-principals list --output json \
  | jq -r ".[] | select(.displayName==\"$SPN_NAME\") | .id")

if [ -z "$SPN_ID" ]; then
  echo "❌ ERROR: SPN $SPN_NAME not found in Databricks"
  exit 1
fi

echo "✅ Databricks SPN ID: $SPN_ID"

# 2️⃣ Create OAuth secret
RESPONSE=$(curl -s -X POST \
  "$DATABRICKS_HOST/api/2.0/accounts/oauth2/secrets" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"service_principal_id\": \"$SPN_ID\",
        \"comment\": \"jenkins-auto-secret\",
        \"lifetime_seconds\": $((EXPIRY_DAYS*24*60*60))
      }")

SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret')

if [ "$SECRET_VALUE" == "null" ] || [ -z "$SECRET_VALUE" ]; then
  echo "❌ ERROR: Secret creation failed"
  echo "$RESPONSE"
  exit 1
fi

echo "✅ OAuth secret created successfully"
echo "------------------------------------------"
echo "SECRET VALUE (COPY & STORE SECURELY):"
echo "$SECRET_VALUE"
echo "------------------------------------------"
