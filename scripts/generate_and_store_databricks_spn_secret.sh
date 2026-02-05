#!/bin/bash
set -e

# --- 1. Variables ---
TARGET_SPN_DISPLAY_NAME=$1
DB_HOST=${DATABRICKS_HOST%/}
DB_TOKEN=${DATABRICKS_ADMIN_TOKEN}

if [ -z "$TARGET_SPN_DISPLAY_NAME" ]; then echo "❌ Error: SPN Name missing"; exit 1; fi

echo "🚀 Starting Workspace-level Secret Generation for: $TARGET_SPN_DISPLAY_NAME"

# --- 2. Get Workspace-level SPN ID ---
echo "🔎 Step 1: Finding SPN in Workspace..."

# SCIM API वापरून Application ID आणि Internal ID मिळवणे
SPN_DATA=$(curl -s -X GET \
  -H "Authorization: Bearer $DB_TOKEN" \
  "$DB_HOST/api/2.0/preview/scim/v2/ServicePrincipals?filter=displayName+eq+%22$TARGET_SPN_DISPLAY_NAME%22")

# लक्षात घ्या: काहीवेळा 'id' हा integer असतो तर काहीवेळा string
INTERNAL_ID=$(echo "$SPN_DATA" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$SPN_DATA" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_ID" ] || [ "$INTERNAL_ID" == "null" ]; then
    echo "❌ Error: SPN '$TARGET_SPN_DISPLAY_NAME' वर्कस्पेसमध्ये सापडला नाही."
    exit 1
fi
echo "✅ Found Workspace SPN ID: $INTERNAL_ID"

# --- 3. Generate OAuth Secret (Alternate Workspace Path) ---
echo "🔐 Step 2: Generating Secret in Workspace..."

# टीप: जर आधीचा एंडपॉइंट चालला नसेल, तर आपण थेट 'Credentials' API वापरू जो UI शी कनेक्ट असतो
API_URL="${DB_HOST}/api/2.0/servicePrincipals/${APP_ID}/credentials/secrets"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${DB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"comment\": \"Generated via Jenkins Pipeline\"}" \
  "$API_URL")

# रिस्पॉन्स तपासा
OAUTH_SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // .client_secret // empty')

if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
    echo "❌ Error: Workspace लेव्हलला सीक्रेट बनवता आले नाही."
    echo "API Response: $RESPONSE"
    echo "💡 टीप: तुमच्या वर्कस्पेसमध्ये OAuth सीक्रेट्स बनवण्याचे अधिकार फक्त Account Console मधूनच असू शकतात."
    exit 1
fi
echo "✅ Workspace Secret Created Successfully!"

# --- 4. Store in Azure Key Vault ---
echo "🚀 Step 3: Storing in Azure Key Vault: $KV_NAME"

az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-dbx-id" --value "$APP_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-dbx-secret" --value "$OAUTH_SECRET_VALUE" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! आता वर्कस्पेस UI मध्ये चेक करा."
echo "----------------------------------------------------"
