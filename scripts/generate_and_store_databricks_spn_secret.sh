#!/bin/bash
set -e

# --- 1. Variables ---
TARGET_SPN_DISPLAY_NAME=$1
ACC_ID=${DATABRICKS_ACCOUNT_ID}
ACCOUNT_API_URL="https://accounts.azuredatabricks.net"

if [ -z "$TARGET_SPN_DISPLAY_NAME" ]; then echo "❌ Error: SPN Name missing"; exit 1; fi
if [ -z "$ACC_ID" ]; then echo "❌ Error: Account ID missing"; exit 1; fi

echo "🚀 Starting Automation for: $TARGET_SPN_DISPLAY_NAME"

# --- 2. Get Account Management Token via Azure CLI ---
echo "🔐 Step 1: Getting Account Management Token from Azure..."

# हे कमांड Azure कडून खास डेटाब्रिक्स अकाउंट कन्सोलसाठी टोकन मिळवते
# Resource ID: 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d (Databricks Resource ID)
DB_ACCOUNT_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query "accessToken" -o tsv)

if [ -z "$DB_ACCOUNT_TOKEN" ]; then
    echo "❌ Error: Azure कडून टोकन मिळाले नाही. कृपया 'az login' तपासा."
    exit 1
fi
echo "✅ Account Token obtained successfully."

# --- 3. Search SPN ---
echo "🔎 Step 2: Searching for SPN in Account Console..."

SEARCH_RESPONSE=$(curl -s -G -X GET \
  -H "Authorization: Bearer $DB_ACCOUNT_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$ACCOUNT_API_URL/api/2.0/accounts/$ACC_ID/scim/v2/ServicePrincipals")

INTERNAL_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_ID" ] || [ "$INTERNAL_ID" == "null" ]; then
  echo "❌ Error: SPN '$TARGET_SPN_DISPLAY_NAME' सापडला नाही."
  echo "Debug Response: $SEARCH_RESPONSE"
  exit 1
fi
echo "✅ Found Internal ID: $INTERNAL_ID"

# --- 4. Generate OAuth Secret ---
echo "🔐 Step 3: Generating OAuth Secret..."

JSON_PAYLOAD=$(cat <<EOF
{
  "lifetime_seconds": 31536000,
  "comment": "oauth-secret-for-$TARGET_SPN_DISPLAY_NAME"
}
EOF
)

SECRET_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DB_ACCOUNT_TOKEN" \
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

# --- 5. Store in Key Vault ---
echo "🚀 Step 4: Storing in Azure Key Vault: $KV_NAME"

az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-dbx-id" --value "$APP_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-dbx-secret" --value "$OAUTH_SECRET_VALUE" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! सर्व डिटेल्स Key Vault मध्ये सेव्ह झाले आहेत."
echo "----------------------------------------------------"
