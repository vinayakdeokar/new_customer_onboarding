#!/bin/bash
set -e

# Arguments
SPN_DISPLAY_NAME=$1

if [ -z "$SPN_DISPLAY_NAME" ]; then echo "❌ SPN name missing"; exit 1; fi

echo "🔐 Step 1: Login Check"
databricks clusters list --page-size 1 > /dev/null
echo "✅ Login OK"

echo "🔎 Step 2: Fetching SPN ID for '$SPN_DISPLAY_NAME'..."

# एकाच कमांडमध्ये सर्व SPNs ची लिस्ट घेणे (हे लूपपेक्षा १०० पट फास्ट आहे)
RAW_JSON=$(databricks service-principals list --output json)

# JQ वापरून 'display_name' किंवा 'displayName' कुठेही नाव मॅच झालं तर ID काढणे
# हे लॉजिक 'service_principals' की मध्ये डेटा असो किंवा डायरेक्ट ॲरेमध्ये, दोन्ही शोधेल
SPN_ID=$(echo "$RAW_JSON" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if type == "object" and .service_principals then
    .service_principals[] | select(.display_name == $NAME or .displayName == $NAME) | .id
  elif type == "array" then
    .[] | select(.display_name == $NAME or .displayName == $NAME) | .id
  else
    .. | objects | select(.display_name == $NAME or .displayName == $NAME) | .id
  end
' | head -n 1)

# जर ID मिळाला नाही तर एरर दाखवून थांबणे
if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
    echo "❌ Error: '$SPN_DISPLAY_NAME' सापडला नाही."
    echo "💡 टीप: एकदा खात्री करा की नाव बरोबर आहे का. उपलब्ध असलेली काही नावे खालीलप्रमाणे आहेत:"
    echo "$RAW_JSON" | jq -r '.. | .display_name? // .displayName? | select(. != null)' | head -n 5
    exit 1
fi

echo "✅ Found SPN ID: $SPN_ID"

echo "🔐 Step 3: Generating OAuth Secret..."
# ३. सिक्रेट जनरेट करणे
SECRET_JSON=$(databricks service-principals secrets create "$SPN_ID" --output json)

CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.client_id')
# काही व्हर्जनमध्ये 'secret' असते तर काहींमध्ये 'client_secret'
CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.secret // .client_secret')

if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" == "null" ]; then
    echo "❌ Error: Secret जनरेट होऊ शकले नाही. Permissions तपासा."
    exit 1
fi

echo "🚀 Step 4: Storing in Azure Key Vault: $KV_NAME"
# ४. Key Vault मध्ये सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-id" --value "$CLIENT_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-secret" --value "$CLIENT_SECRET" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! $SPN_DISPLAY_NAME साठी काम पूर्ण झाले."
echo "Final ID: $SPN_ID"
echo "----------------------------------------------------"
