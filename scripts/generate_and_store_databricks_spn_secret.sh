#!/bin/bash
set -e

SPN_DISPLAY_NAME=$1
if [ -z "$SPN_DISPLAY_NAME" ]; then echo "❌ SPN name missing"; exit 1; fi

echo "🔐 Step 1: Login Check"
databricks clusters list --page-size 1 > /dev/null
echo "✅ Login OK"

echo "🔎 Step 2: Searching for SPN..."

# १. सर्व SPNs चे फक्त नाव आणि ID प्रिंट करा (Debug साठी)
echo "--- Current SPNs accessible by this token ---"
databricks service-principals list --output json | jq -r 'if type=="array" then .[] | "\(.display_name) (ID: \(.id))" else .service_principals[] | "\(.display_name) (ID: \(.id))" end' || echo "No SPNs visible!"
echo "--------------------------------------------"

# २. आता तुमचा स्पेसिफिक SPN शोधण्याचा प्रयत्न करा
RAW_JSON=$(databricks service-principals list --output json)

SPN_ID=$(echo "$RAW_JSON" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if type=="array" then .[] | select(.display_name==$NAME) | .id
  else .service_principals[] | select(.display_name==$NAME) | .id end
' | head -n 1)

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
  echo "❌ Error: SPN '$SPN_DISPLAY_NAME' अजूनही सापडला नाही."
  echo "💡 उपाय: तुमच्या Databricks Admin ला सांगा की Jenkins युजरला 'Admin' ग्रुपमध्ये ॲड करा किंवा या SPN ला वर्कस्पेसमध्ये 'Manage' परमिशन द्या."
  exit 1
fi

echo "✅ Found ID: $SPN_ID"

# ३. सिक्रेट जनरेट करणे
echo "🔐 Step 3: Generating Secret..."
SECRET_JSON=$(databricks service-principals secrets create "$SPN_ID" --output json)

# नवीन CLI मध्ये 'secret' की असू शकते, जुन्यात 'client_secret'
CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.secret // .client_secret')

# ४. Key Vault मध्ये सेव्ह करणे
echo "🚀 Step 4: Storing in Key Vault..."
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-id" --value "$CLIENT_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-secret" --value "$CLIENT_SECRET" --output none

echo "🎉 यशस्वीपणे पूर्ण झाले!"
