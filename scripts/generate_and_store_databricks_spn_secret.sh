#!/bin/bash
set -e

# --- 1. Variables & Environment Checks ---
TARGET_SPN_DISPLAY_NAME=$1
# टोकन आणि अकाउंट आयडी मिळवणे
DB_TOKEN=${DATABRICKS_ADMIN_TOKEN}
ACC_ID=${DATABRICKS_ACCOUNT_ID}

# अकाउंट लेव्हल API साठी ग्लोबल URL वापरणे अनिवार्य आहे
ACCOUNT_API_URL="https://accounts.azuredatabricks.net"

if [ -z "$TARGET_SPN_DISPLAY_NAME" ]; then echo "❌ Error: SPN Name missing"; exit 1; fi
if [ -z "$DB_TOKEN" ]; then echo "❌ Error: Admin Token missing"; exit 1; fi
if [ -z "$ACC_ID" ]; then echo "❌ Error: Account ID missing"; exit 1; fi

echo "🚀 Starting Automation for: $TARGET_SPN_DISPLAY_NAME"
echo "ℹ️  Using Account API: $ACCOUNT_API_URL"

# --- 2. Fetch SPN Internal ID (Account Level) ---
echo "🔎 Step 1: Searching for SPN in Account Console..."

# लक्षात घ्या: इथे आपण $ACCOUNT_API_URL वापरत आहोत
SEARCH_RESPONSE=$(curl -s -G -X GET \
  -H "Authorization: Bearer $DB_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$ACCOUNT_API_URL/api/2.0/accounts/$ACC_ID/scim/v2/ServicePrincipals")

INTERNAL_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_ID" ] || [ "$INTERNAL_ID" == "null" ]; then
  echo "❌ Error: SPN सापडला नाही किंवा API ला रस्ता मिळाला नाही."
  echo "Debug Response: $SEARCH_RESPONSE"
  exit 1
fi

echo "✅ Found Internal ID: $INTERNAL_ID"
echo "✅ Found Application ID: $APP_ID"

# --- 3. Generate OAuth Secret ---
echo "🔐 Step 2: Generating OAuth Secret..."

JSON_PAYLOAD=$(cat <<EOF
{
  "lifetime_seconds": 31536000,
  "comment": "secret-for-$TARGET_SPN_DISPLAY_NAME"
}
EOF
)

SECRET_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$ACCOUNT_API_URL/api/2.0/accounts/$ACC_ID/servicePrincipals/$INTERNAL_ID/credentials/secrets")

OAUTH_SECRET_VALUE=$(echo "$SECRET_RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
  echo "❌ Error: Secret जनरेट झाले नाही."
  echo "Debug: $SECRET_RESPONSE"
  exit 1
fi

echo "✅ Secret Created Successfully!"

# --- 4. Store in Azure Key Vault ---
echo "🚀 Step 3: Storing in Azure Key Vault: $KV_NAME"

az keyvault secret set --vault-name "$KV_NAME" \
    --name "${TARGET_SPN_DISPLAY_NAME}-dbx-id" \
    --value "$APP_ID" --output none

az keyvault secret set --vault-name "$KV_NAME" \
    --name "${TARGET_SPN_DISPLAY_NAME}-dbx-secret" \
    --value "$OAUTH_SECRET_VALUE" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! $TARGET_SPN_DISPLAY_NAME चे काम फत्ते झाले."
echo "----------------------------------------------------"
