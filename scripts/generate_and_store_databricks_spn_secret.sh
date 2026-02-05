#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
TARGET_SPN_DISPLAY_NAME=$1
WORKSPACE_URL=${DATABRICKS_HOST%/} # e.g., https://adb-xxx.azuredatabricks.net
TOKEN=${DATABRICKS_ADMIN_TOKEN}

echo "🚀 Starting Workspace-level Secret Generation for: $TARGET_SPN_DISPLAY_NAME"

# --- 2. FIND WORKSPACE-LEVEL SPN ID ---
# डॉक्युमेंटनुसार आधी वर्कस्पेसमध्ये तो SPN शोधणे गरजेचे आहे
echo "🔎 Step 1: Finding Workspace-level ID..."
SPN_DATA=$(curl -s -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "$WORKSPACE_URL/api/2.0/preview/scim/v2/ServicePrincipals?filter=displayName+eq+%22$TARGET_SPN_DISPLAY_NAME%22")

# हा तो 'Internal Workspace ID' आहे जो सीक्रेट बनवण्यासाठी लागतो
INTERNAL_WS_ID=$(echo "$SPN_DATA" | jq -r '.Resources[0].id // empty')
APPLICATION_ID=$(echo "$SPN_DATA" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_WS_ID" ] || [ "$INTERNAL_WS_ID" == "null" ]; then
    echo "❌ Error: SPN '$TARGET_SPN_DISPLAY_NAME' वर्कस्पेसमध्ये सापडला नाही."
    exit 1
fi
echo "✅ Found Workspace ID: $INTERNAL_WS_ID"

# --- 3. GENERATE SECRET (As per Microsoft Documentation) ---
# हाच तो एंडपॉइंट आहे जो तुझ्या स्क्रीनशॉटमधील टॅबमध्ये सीक्रेट दाखवेल
echo "🔐 Step 2: Generating OAuth Secret in Workspace..."
API_PATH="$WORKSPACE_URL/api/2.0/servicePrincipals/$INTERNAL_WS_ID/secrets"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"comment\": \"Created via Automation for $TARGET_SPN_DISPLAY_NAME\"}" \
  "$API_PATH")

SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // empty')

if [ -z "$SECRET_VALUE" ] || [ "$SECRET_VALUE" == "null" ]; then
    echo "❌ Error: सीक्रेट बनवता आले नाही. रिस्पॉन्स तपासा:"
    echo "$RESPONSE"
    exit 1
fi

echo "✅ Secret Created Successfully!"

# --- 4. STORE IN KEY VAULT ---
echo "🚀 Storing in Azure Key Vault..."
az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-id" --value "$APPLICATION_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-secret" --value "$SECRET_VALUE" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! आता तुझ्या वर्कस्पेस UI मध्ये 'Secrets' टॅब रिफ्रेश करून बघ."
