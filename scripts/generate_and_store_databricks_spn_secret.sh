#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
TARGET_SPN_DISPLAY_NAME=$1
WORKSPACE_URL=${DATABRICKS_HOST%/}
TOKEN=${DATABRICKS_ADMIN_TOKEN}

echo "🚀 Documentation-based Automation starting for: $TARGET_SPN_DISPLAY_NAME"

# --- 2. GET WORKSPACE ID & APPLICATION ID ---
# डॉक्युमेंटप्रमाणे SCIM API वापरून आधी माहिती काढणे
echo "🔎 Step 1: Fetching SPN info from Workspace..."
SPN_DATA=$(curl -s -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "$WORKSPACE_URL/api/2.0/preview/scim/v2/ServicePrincipals?filter=displayName+eq+%22$TARGET_SPN_DISPLAY_NAME%22")

WS_INTERNAL_ID=$(echo "$SPN_DATA" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$SPN_DATA" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$WS_INTERNAL_ID" ]; then
    echo "❌ Error: SPN सापडला नाही."
    exit 1
fi

echo "✅ Found ID: $WS_INTERNAL_ID"

# --- 3. CREATE SECRET (Using the CORRECT Documentation Endpoint) ---
# 💡 लक्ष द्या: डॉक्युमेंटनुसार, काही टॅन्ट्समध्ये एंडपॉइंट असा असतो:
echo "🔐 Step 2: Generating OAuth Secret..."

# आपण आता 'accounts' पाथ न वापरता वर्कस्पेसच्या सुसंगत एंडपॉइंटला हिट करू
# जर /secrets चालत नसेल, तर डॉक्युमेंट /credentials/secrets सुचवते
API_URL="$WORKSPACE_URL/api/2.0/servicePrincipals/$APP_ID/secrets"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"comment\": \"Workspace Secret for Automation\"}" \
  "$API_URL")

# --- 4. ERROR HANDLING & RESULT ---
OAUTH_SECRET=$(echo "$RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET" ]; then
    echo "❌ रिस्पॉन्समध्ये सीक्रेट मिळाले नाही."
    echo "API Response: $RESPONSE"
    
    # जर अजूनही ENDPOINT_NOT_FOUND आला, तर डॉक्युमेंटमधील 'Note' नुसार:
    echo "------------------------------------------------"
    echo "💡 डॉक्युमेंटमधील 'Important' नोट सांगते की: "
    echo "काही Azure Regions मध्ये 'Workspace-level' API डिसेबल केले गेले आहेत."
    echo "त्यांच्यासाठी फक्त Account-level API (जे आपण आधी केलं) हेच अधिकृत आहे."
    exit 1
fi

echo "✅ SUCCESS! सीक्रेट तयार झाले."
echo "🚀 Storing in Key Vault..."
az keyvault secret set --vault-name "$KV_NAME" --name "${TARGET_SPN_DISPLAY_NAME}-secret" --value "$OAUTH_SECRET" --output none
