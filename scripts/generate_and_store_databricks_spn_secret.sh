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

# JQ वापरून ID आणि Application ID (Client ID) काढणे
# आपण application_id आणि applicationId दोन्ही चेक करत आहोत
SPN_DATA=$(echo "$RAW_LIST" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if type == "object" and .service_principals then .service_principals[] 
  elif type == "array" then .[] 
  else .. | objects end | select(.display_name == $NAME or .displayName == $NAME)
')

SPN_ID=$(echo "$SPN_DATA" | jq -r '.id')
OAUTH_CLIENT_ID=$(echo "$SPN_DATA" | jq -r '.application_id // .applicationId')

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
    echo "❌ Error: '$SPN_DISPLAY_NAME' सापडला नाही. कृपया स्पेलिंग तपासा."
    exit 1
fi

echo "✅ Found SPN ID: $SPN_ID"
echo "✅ Found Client ID: $OAUTH_CLIENT_ID"

echo "🔐 Step 3: Generating OAuth Secret via API..."

# अचूक API पाथ: /2.0/service-principals/{id}/secrets
# (येथे service-principals मध्ये हायफन असणे गरजेचे आहे)
API_RESPONSE=$(databricks api post /2.0/service-principals/$SPN_ID/secrets)

# API मधून सिक्रेट काढणे (येथे की 'secret' किंवा 'client_secret' असू शकते)
OAUTH_CLIENT_SECRET=$(echo "$API_RESPONSE" | jq -r '.secret // .client_secret')

if [ -z "$OAUTH_CLIENT_SECRET" ] || [ "$OAUTH_CLIENT_SECRET" == "null" ]; then
    echo "❌ Error: Secret जनरेट झाले नाही. API Response: $API_RESPONSE"
    exit 1
fi

echo "✅ OAuth secret generated successfully"

echo "🚀 Step 4: Storing in Azure Key Vault: $KV_NAME"
# Key Vault मध्ये सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-dbx-id" --value "$OAUTH_CLIENT_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-dbx-secret" --value "$OAUTH_CLIENT_SECRET" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! $SPN_DISPLAY_NAME साठी सिक्रेट्स स्टोअर झाले आहेत."
echo "Key 1: ${SPN_DISPLAY_NAME}-dbx-id"
echo "Key 2: ${SPN_DISPLAY_NAME}-dbx-secret"
echo "----------------------------------------------------"
