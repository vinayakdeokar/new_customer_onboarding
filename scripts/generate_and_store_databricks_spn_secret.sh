#!/bin/bash
set -e

# Arguments & Env Variables
SPN_DISPLAY_NAME=$1
# Jenkins मधून मिळणारे Credentials
DB_HOST=${DATABRICKS_HOST%/} # शेवटी स्लॅश असेल तर काढण्यासाठी
DB_TOKEN=${DATABRICKS_ADMIN_TOKEN}

if [ -z "$SPN_DISPLAY_NAME" ]; then echo "❌ SPN name missing"; exit 1; fi
if [ -z "$DB_HOST" ] || [ -z "$DB_TOKEN" ]; then echo "❌ Databricks Host/Token missing in Env"; exit 1; fi

echo "🔐 Step 1: Login Check"
databricks clusters list --page-size 1 > /dev/null
echo "✅ Login OK"

echo "🔎 Step 2: Resolving SPN Details for '$SPN_DISPLAY_NAME'..."

# SPN ची माहिती मिळवणे (ID आणि Application ID)
RAW_LIST=$(databricks service-principals list --output json)

SPN_DATA=$(echo "$RAW_LIST" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if type == "object" and .service_principals then .service_principals[] 
  elif type == "array" then .[] 
  else .. | objects end | select(.display_name == $NAME or .displayName == $NAME)
')

SPN_ID=$(echo "$SPN_DATA" | jq -r '.id')
OAUTH_CLIENT_ID=$(echo "$SPN_DATA" | jq -r '.application_id // .applicationId')

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
    echo "❌ Error: '$SPN_DISPLAY_NAME' सापडला नाही. कृपया नाव तपासा."
    exit 1
fi

echo "✅ Found SPN ID: $SPN_ID"
echo "✅ Found Client ID: $OAUTH_CLIENT_ID"

echo "🔐 Step 3: Generating OAuth Secret via Direct REST API..."

# CLI ऐवजी थेट CURL वापरून API कॉल करणे
# Endpoint: /api/2.0/servicePrincipals/{id}/secrets
API_URL="${DB_HOST}/api/2.0/servicePrincipals/${SPN_ID}/secrets"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${DB_TOKEN}" \
  -H "Content-Type: application/json" \
  "$API_URL")

# रिस्पॉन्स मधून सिक्रेट काढणे
OAUTH_CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.secret // .client_secret')

if [ -z "$OAUTH_CLIENT_SECRET" ] || [ "$OAUTH_CLIENT_SECRET" == "null" ]; then
    echo "❌ Error: Secret जनरेट झाले नाही. API Response: $RESPONSE"
    exit 1
fi

echo "✅ OAuth secret generated successfully"

echo "🚀 Step 4: Storing in Azure Key Vault: $KV_NAME"

# Client ID सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" \
    --name "${SPN_DISPLAY_NAME}-dbx-id" \
    --value "$OAUTH_CLIENT_ID" --output none

# Secret सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" \
    --name "${SPN_DISPLAY_NAME}-dbx-secret" \
    --value "$OAUTH_CLIENT_SECRET" --output none

echo "----------------------------------------------------"
echo "🎉 FINAL SUCCESS! $SPN_DISPLAY_NAME साठी सर्व माहिती KV मध्ये स्टोअर झाली."
echo "ID: $SPN_ID"
echo "Client ID: $OAUTH_CLIENT_ID"
echo "----------------------------------------------------"
