#!/bin/bash
set -e

# --- 1. Variables & Environment Checks ---
TARGET_SPN_DISPLAY_NAME=$1
DB_HOST=${DATABRICKS_HOST%/}
DB_TOKEN=${DATABRICKS_ADMIN_TOKEN}
# Jenkins मध्ये हे Environment Variable सेट असणे गरजेचे आहे, किंवा इथे हार्डकोड करा
# उदा: ACCOUNT_ID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
ACC_ID=${DATABRICKS_ACCOUNT_ID} 

if [ -z "$TARGET_SPN_DISPLAY_NAME" ]; then echo "❌ Error: SPN Name argument missing"; exit 1; fi
if [ -z "$DB_HOST" ] || [ -z "$DB_TOKEN" ]; then echo "❌ Error: Host/Token Env variables missing"; exit 1; fi
if [ -z "$ACC_ID" ]; then 
    echo "❌ Error: DATABRICKS_ACCOUNT_ID variable missing in Jenkins."
    exit 1
fi

echo "🚀 Starting Automation for SPN: $TARGET_SPN_DISPLAY_NAME"
echo "ℹ️  Using Account ID: $ACC_ID"

# --- 2. Fetch SPN Internal ID (Using Account SCIM API) ---
echo "🔎 Step 1: Searching for SPN in Account Console..."

# तुमच्या रेफरन्स कोडनुसार SCIM API कॉल
SEARCH_RESPONSE=$(curl -s -G -X GET \
  -H "Authorization: Bearer $DB_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$DB_HOST/api/2.0/accounts/$ACC_ID/scim/v2/ServicePrincipals")

# ID आणि Application ID काढणे
INTERNAL_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_ID" ] || [ "$INTERNAL_ID" == "null" ]; then
  echo "❌ Error: SPN '$TARGET_SPN_DISPLAY_NAME' not found in Account $ACC_ID."
  echo "Debug Response: $SEARCH_RESPONSE"
  exit 1
fi

echo "✅ Found Internal ID: $INTERNAL_ID"
echo "✅ Found Application ID: $APP_ID"

# --- 3. Generate OAuth Secret (Using Account Credentials API) ---
echo "🔐 Step 2: Generating OAuth Secret..."

JSON_PAYLOAD=$(cat <<EOF
{
  "lifetime_seconds": 31536000,
  "comment": "oauth-secret-for-$TARGET_SPN_DISPLAY_NAME-jenkins"
}
EOF
)

# तुमच्या रेफरन्स कोडनुसार Secret Create API कॉल
SECRET_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$DB_HOST/api/2.0/accounts/$ACC_ID/servicePrincipals/$INTERNAL_ID/credentials/secrets")

OAUTH_SECRET_VALUE=$(echo "$SECRET_RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
  echo "❌ Error: Secret जनरेट झाले नाही."
  echo "Debug Response: $SECRET_RESPONSE"
  exit 1
fi

echo "✅ Secret Created Successfully!"

# --- 4. Store in Azure Key Vault ---
echo "🚀 Step 3: Storing in Azure Key Vault: $KV_NAME"

# Client ID स्टोअर करणे
az keyvault secret set --vault-name "$KV_NAME" \
    --name "${TARGET_SPN_DISPLAY_NAME}-dbx-id" \
    --value "$APP_ID" --output none

# Secret स्टोअर करणे
az keyvault secret set --vault-name "$KV_NAME" \
    --name "${TARGET_SPN_DISPLAY_NAME}-dbx-secret" \
    --value "$OAUTH_SECRET_VALUE" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! Automation पूर्ण झाले."
echo "SPN: $TARGET_SPN_DISPLAY_NAME"
echo "Application ID: $APP_ID"
echo "----------------------------------------------------"
