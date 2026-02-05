#!/bin/bash
set -e

# --- 1. Setup ---
TARGET_SPN_DISPLAY_NAME=$1
DATABRICKS_TOKEN=${DATABRICKS_ADMIN_TOKEN}
ACCOUNT_ID=${DATABRICKS_ACCOUNT_ID}

# 💡 महत्त्वाचा बदल: अकाउंट लेव्हल कॉलसाठी हीच URL लागते
# तुझ्या मित्राच्या स्क्रिप्टमध्ये कदाचित ही URL बॅकएंडला सेट असेल
ACCOUNTS_BASE_URL="https://accounts.azuredatabricks.net"

if [ -z "$TARGET_SPN_DISPLAY_NAME" ]; then echo "Error: SPN Name missing"; exit 1; fi
if [ -z "$ACCOUNT_ID" ]; then echo "Error: ACCOUNT_ID missing"; exit 1; fi

echo "🚀 Starting Reference-based Automation for: $TARGET_SPN_DISPLAY_NAME"
echo "ℹ️  Using Account ID: $ACCOUNT_ID"

# --- 2. Fetch SPN Data (Step 1 from friend's script) ---
# इथे आपण $ACCOUNTS_BASE_URL वापरत आहोत जेणेकरून SPN सापडेल
RESPONSE=$(curl -s -G -X GET \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$ACCOUNTS_BASE_URL/api/2.0/accounts/$ACCOUNT_ID/scim/v2/ServicePrincipals")

INTERNAL_ID=$(echo "$RESPONSE" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$RESPONSE" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_ID" ] || [ "$INTERNAL_ID" == "null" ]; then
  echo "Error: SPN '$TARGET_SPN_DISPLAY_NAME' not found in Account Console."
  echo "Debug Response: $RESPONSE"
  exit 1
fi

echo "✅ Internal ID: $INTERNAL_ID"
echo "✅ Application ID: $APP_ID"

# --- 3. Generate Secret (Step 2 from friend's script) ---
JSON_PAYLOAD=$(cat <<EOF
{
  "lifetime_seconds": 31536000,
  "comment": "oauth-secret-for-$TARGET_SPN_DISPLAY_NAME"
}
EOF
)

SECRET_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$ACCOUNTS_BASE_URL/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$INTERNAL_ID/credentials/secrets")

OAUTH_SECRET_VALUE=$(echo "$SECRET_RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
  echo "Failed to generate secret. Response: $SECRET_RESPONSE"
  exit 1
fi

echo "✅ Secret Generated Successfully!"

# --- 4. Storing in Azure Key Vault ---
echo "🚀 Storing details in Key Vault: $KV_NAME"

az keyvault secret set --vault-name "$KV_NAME" \
    --name "${TARGET_SPN_DISPLAY_NAME}-dbx-id" \
    --value "$APP_ID" --output none

az keyvault secret set --vault-name "$KV_NAME" \
    --name "${TARGET_SPN_DISPLAY_NAME}-dbx-secret" \
    --value "$OAUTH_SECRET_VALUE" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! Automation complete."
