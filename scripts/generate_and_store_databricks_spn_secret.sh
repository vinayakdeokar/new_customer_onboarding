#!/bin/bash
set -e

# Arguments आणि Environment Variables
SPN_DISPLAY_NAME=$1

if [ -z "$SPN_DISPLAY_NAME" ]; then
  echo "❌ Error: SPN display name missing"
  exit 1
fi

if [ -z "$KV_NAME" ]; then
  echo "❌ Error: KV_NAME missing"
  exit 1
fi

echo "🔐 Step 1: Verify Databricks CLI login"
# नवीन CLI साठी 'page-size' वापरला आहे
databricks clusters list --page-size 1 > /dev/null
echo "✅ Databricks CLI login OK"

echo "🔎 Step 2: Resolve Databricks SPN ID for: $SPN_DISPLAY_NAME"

# सर्व SPNs ची लिस्ट काढणे
RAW_JSON=$(databricks service-principals list --output json)

# जर डेटा रिकामी असेल तर परवानग्या तपासा
if [ -z "$RAW_JSON" ] || [ "$RAW_JSON" == "[]" ]; then
  echo "❌ Error: No Service Principals found or No Access. Check Admin permissions."
  exit 1
fi

# नवीन आणि जुन्या CLI नुसार ID शोधणे
SPN_ID=$(echo "$RAW_JSON" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if type == "array" then
    .[] | select(.display_name == $NAME) | .id
  elif .service_principals then
    .service_principals[] | select(.display_name == $NAME) | .id
  else
    empty
  end
' | head -n 1)

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
  echo "❌ SPN not found: $SPN_DISPLAY_NAME"
  exit 1
fi

echo "✅ SPN ID resolved: $SPN_ID"

echo "🔐 Step 3: Generate OAuth secret"

# नवीन CLI मध्ये 'secrets' कमांड अशी चालते
# टीप: जर आधीच सिक्रेट असेल तर हे नवीन तयार करेल
SECRET_JSON=$(databricks service-principals secrets create "$SPN_ID" --output json)

OAUTH_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.client_id')
OAUTH_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.secret || .client_secret')

if [ -z "$OAUTH_CLIENT_SECRET" ] || [ "$OAUTH_CLIENT_SECRET" == "null" ]; then
  echo "❌ OAuth secret generation failed!"
  exit 1
fi

echo "✅ OAuth secret generated"

echo "🔐 Step 4: Store in Azure Key Vault: $KV_NAME"

# Client ID सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-dbx-client-id" --value "$OAUTH_CLIENT_ID" --output none

# Secret सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-dbx-client-secret" --value "$OAUTH_CLIENT_SECRET" --output none

echo "🎉 DONE: Secrets successfully stored in Key Vault!"
