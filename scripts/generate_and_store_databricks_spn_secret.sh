#!/bin/bash
set -e

# Arguments
SPN_DISPLAY_NAME=$1

if [ -z "$SPN_DISPLAY_NAME" ]; then echo "❌ SPN name missing"; exit 1; fi

echo "🔐 Step 1: Login Check"
databricks clusters list --page-size 1 > /dev/null
echo "✅ Login OK"

echo "🔎 Step 2: Fetching SPN Details for '$SPN_DISPLAY_NAME'..."

# सर्व SPNs ची माहिती मिळवणे
RAW_LIST=$(databricks service-principals list --output json)

# JQ वापरून ID आणि Application ID दोन्ही शोधणे
SPN_DATA=$(echo "$RAW_LIST" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if type == "object" and .service_principals then .service_principals[] 
  elif type == "array" then .[] 
  else .. | objects end | select(.display_name == $NAME or .displayName == $NAME)
')

SPN_ID=$(echo "$SPN_DATA" | jq -r '.id')
OAUTH_CLIENT_ID=$(echo "$SPN_DATA" | jq -r '.application_id // .applicationId')

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
    echo "❌ Error: '$SPN_DISPLAY_NAME' सापडला नाही."
    exit 1
fi

echo "✅ Found SPN ID: $SPN_ID"
echo "✅ Found Client ID: $OAUTH_CLIENT_ID"

echo "🔐 Step 3: Generating OAuth Secret via Correct API..."

# ✅ एकदम अचूक API पाथ: /api/2.0/servicePrincipals/{id}/secrets
# यात हायफन नाही आणि 'api' प्रीफिक्स आहे.
API_RESPONSE=$(databricks api post /api/2.0/servicePrincipals/$SPN_ID/secrets)

# रिस्पॉन्स मधून सिक्रेट काढणे
OAUTH_CLIENT_SECRET=$(echo "$API_RESPONSE" | jq -r '.secret // .client_secret')

if [ -z "$OAUTH_CLIENT_SECRET" ] || [ "$OAUTH_CLIENT_SECRET" == "null" ]; then
    echo "❌ Error: Secret जनरेट झाले नाही. API Response: $API_RESPONSE"
    exit 1
fi

echo "✅ OAuth secret generated successfully"

echo "🚀 Step 4: Storing in Azure Key Vault: $KV_NAME"

# Key Vault मध्ये Client ID सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-dbx-id" --value "$OAUTH_CLIENT_ID" --output none

# Key Vault मध्ये Secret सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-dbx-secret" --value "$OAUTH_CLIENT_SECRET" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! Automation यशस्वी झाले."
echo "ID: $SPN_ID"
echo "Key Vault मध्ये डेटा सेव्ह झाला आहे."
echo "----------------------------------------------------"
