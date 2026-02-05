#!/bin/bash
set -e

# --- 1. Setup ---
TARGET_SPN_DISPLAY_NAME=$1
ACCOUNT_ID=${DATABRICKS_ACCOUNT_ID}
ACCOUNTS_BASE_URL="https://accounts.azuredatabricks.net"

if [ -z "$TARGET_SPN_DISPLAY_NAME" ]; then echo "Error: SPN Name missing"; exit 1; fi
if [ -z "$ACCOUNT_ID" ]; then echo "Error: ACCOUNT_ID missing"; exit 1; fi

echo "🚀 Starting Reference-based Automation for: $TARGET_SPN_DISPLAY_NAME"

# --- 2. GET CORRECT TOKEN (ही स्टेप महत्त्वाची आहे) ---
echo "🔐 Fetching Account Management Token from Azure..."

# Azure CLI कडून डेटाब्रिक्स अकाउंट मॅनेजमेंटसाठी टोकन मिळवणे
# हे टोकन 401 एरर कायमचा घालवेल
DB_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query "accessToken" -o tsv)

if [ -z "$DB_TOKEN" ]; then
    echo "❌ Error: Azure कडून टोकन मिळाले नाही."
    exit 1
fi
echo "✅ Token obtained successfully."

# --- 3. Fetch SPN Data (Using Friend's logic) ---
echo "🔎 Searching for SPN..."
RESPONSE=$(curl -s -G -X GET \
  -H "Authorization: Bearer $DB_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$ACCOUNTS_BASE_URL/api/2.0/accounts/$ACCOUNT_ID/scim/v2/ServicePrincipals")

INTERNAL_ID=$(echo "$RESPONSE" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$RESPONSE" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_ID" ] || [ "$INTERNAL_ID" == "null" ]; then
  echo "❌ Error: SPN '$TARGET_SPN_DISPLAY_NAME' not found."
  echo "Debug Response: $RESPONSE"
  exit 1
fi
echo "✅ Found IDs: Internal=$INTERNAL_ID, App=$APP_ID"

# --- 4. Generate Secret (Using Friend's logic) ---
echo "🔐 Generating OAuth Secret..."
JSON_PAYLOAD=$(cat <<EOF
{
  "lifetime_seconds": 31536000,
  "comment": "oauth-secret-for-$TARGET_SPN_DISPLAY_NAME"
}
EOF
)

SECRET_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$ACCOUNTS_BASE_URL/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$INTERNAL_ID/credentials/secrets")

OAUTH_SECRET_VALUE=$(echo "$SECRET_RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
  echo "❌ Failed to generate secret. Response: $SECRET_RESPONSE"
  exit 1
fi
echo "✅ Secret Created Successfully!"

# --- 5. Storing in Azure Key Vault ---
echo "🚀 Storing details in Key Vault: $KV_NAME"

az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-dbx-id" --value "$APP_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-dbx-secret" --value "$OAUTH_SECRET_VALUE" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! $TARGET_SPN_DISPLAY_NAME automation complete."
