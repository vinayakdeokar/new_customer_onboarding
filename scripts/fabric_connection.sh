#!/bin/bash
set -e

echo "======================================="
echo "🚀 POWER BI FABRIC CONNECTION AUTOMATION"
echo "======================================="

# ==============================
# REQUIRED ENV VARIABLES
# ==============================
: "${DISPLAY_NAME:?Missing DISPLAY_NAME}"
: "${GATEWAY_ID:?Missing GATEWAY_ID}"
: "${DB_HOST:?Missing DB_HOST}"
: "${DB_HTTP_PATH:?Missing DB_HTTP_PATH}"
: "${DB_USER:?Missing DB_USER}"
: "${DB_PASS:?Missing DB_PASS}"

# ==============================
# GET ACCESS TOKEN
# ==============================
echo "🔐 Getting Power BI access token..."
TOKEN=$(az account get-access-token \
  --resource https://analysis.windows.net/powerbi/api \
  --query accessToken -o tsv)

if [ -z "$TOKEN" ]; then
  echo "❌ Failed to get access token"
  exit 1
fi

# ==============================
# CHECK IF CONNECTION EXISTS
# ==============================
echo "🔍 Checking if connection already exists..."

EXISTING_ID=$(curl -s https://api.powerbi.com/v1.0/myorg/connections \
  -H "Authorization: Bearer $TOKEN" \
  | jq -r ".value[] | select(.displayName==\"$DISPLAY_NAME\") | .id")

if [ ! -z "$EXISTING_ID" ]; then
  echo "⚠️ Connection already exists with ID: $EXISTING_ID"
  echo "✅ Skipping creation."
  exit 0
fi

# ==============================
# CREATE CONNECTION
# ==============================
echo "🚀 Creating new connection..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  https://api.powerbi.com/v1.0/myorg/connections \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"displayName\": \"$DISPLAY_NAME\",
    \"connectivityType\": \"VirtualNetworkGateway\",
    \"gatewayId\": \"$GATEWAY_ID\",
    \"privacyLevel\": \"Private\",
    \"connectionDetails\": {
      \"type\": \"Databricks\",
      \"creationMethod\": \"Databricks.Catalogs\",
      \"values\": [
        { \"name\": \"host\", \"value\": \"$DB_HOST\" },
        { \"name\": \"httpPath\", \"value\": \"$DB_HTTP_PATH\" }
      ]
    },
    \"credentialDetails\": {
      \"credentialType\": \"Basic\",
      \"singleSignOnType\": \"None\",
      \"connectionEncryption\": \"NotEncrypted\",
      \"skipTestConnection\": true,
      \"credentials\": {
        \"credentialType\": \"Basic\",
        \"username\": \"$DB_USER\",
        \"password\": \"$DB_PASS\"
      }
    }
  }")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

echo "HTTP Status: $HTTP_CODE"
echo "Response:"
echo "$HTTP_BODY"

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Connection Created Successfully!"
else
  echo "❌ Connection creation failed!"
  exit 1
fi
