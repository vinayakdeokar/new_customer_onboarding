#!/bin/bash
set -e

# १. व्हेरिएबल्स
TARGET_SPN_DISPLAY_NAME=$1
DB_HOST=${DATABRICKS_HOST%/}
DB_TOKEN=${DATABRICKS_ADMIN_TOKEN}

echo "🔎 Step 1: Searching SPN in Workspace..."

# वर्कस्पेस लेव्हल SCIM API वापरून ID शोधणे
SPN_DATA=$(curl -s -X GET \
  -H "Authorization: Bearer $DB_TOKEN" \
  "$DB_HOST/api/2.0/preview/scim/v2/ServicePrincipals?filter=displayName+eq+%22$TARGET_SPN_DISPLAY_NAME%22")

# इथून आपण Application ID (जो 7eceb... असा आहे) तो घेणार आहोत
APP_ID=$(echo "$SPN_DATA" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$APP_ID" ] || [ "$APP_ID" == "null" ]; then
    echo "❌ Error: SPN '$TARGET_SPN_DISPLAY_NAME' सापडला नाही."
    exit 1
fi

echo "✅ Found Application ID: $APP_ID"

echo "🔐 Step 2: Generating Secret specifically for Workspace UI..."

# 💡 महत्त्वाचा बदल: इथे आपण 'accounts' पाथ वापरत नाहीये
# आपण थेट वर्कस्पेसच्या /servicePrincipals/{id}/secrets एंडपॉइंटला हिट करतोय
API_URL="${DB_HOST}/api/2.0/servicePrincipals/${APP_ID}/secrets"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${DB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"comment\": \"Created for Workspace UI\"}" \
  "$API_URL")

OAUTH_SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // .client_secret // empty')

if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
    echo "❌ Error: Workspace UI साठी सीक्रेट बनवता आले नाही."
    echo "API Response: $RESPONSE"
    echo "------------------------------------------------"
    echo "💡 जर हा 'ENDPOINT_NOT_FOUND' देत असेल, तर याचा अर्थ तुमच्या डेटाब्रिक्स टियरमध्ये"
    echo "UI मधून सीक्रेट बनवणे API द्वारे अलाउड नाही. अशा वेळी अकाउंट लेवलच वापरावे लागेल."
    exit 1
fi

echo "✅ Secret Created Successfully in Workspace!"

# Azure Key Vault मध्ये सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-dbx-id" --value "$APP_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-dbx-secret" --value "$OAUTH_SECRET_VALUE" --output none

echo "🎉 मिशन यशस्वी! आता वर्कस्पेस रिफ्रेश करून बघ."
