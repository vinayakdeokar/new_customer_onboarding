#!/bin/bash
set -e

# Arguments
SPN_DISPLAY_NAME=$1

if [ -z "$SPN_DISPLAY_NAME" ]; then echo "❌ SPN name missing"; exit 1; fi

echo "🔐 Step 1: Login Check"
databricks clusters list --page-size 1 > /dev/null
echo "✅ Login OK"

echo "🔎 Step 2: Fetching SPN ID for '$SPN_DISPLAY_NAME'..."

# सर्व SPNs ची लिस्ट घेऊन JQ ने ID शोधणे
RAW_JSON=$(databricks service-principals list --output json)

SPN_ID=$(echo "$RAW_JSON" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if type == "object" and .service_principals then
    .service_principals[] | select(.display_name == $NAME or .displayName == $NAME) | .id
  elif type == "array" then
    .[] | select(.display_name == $NAME or .displayName == $NAME) | .id
  else
    .. | objects | select(.display_name == $NAME or .displayName == $NAME) | .id
  end
' | head -n 1)

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
    echo "❌ Error: '$SPN_DISPLAY_NAME' सापडला नाही."
    exit 1
fi

echo "✅ Found SPN ID: $SPN_ID"

echo "🔐 Step 3: Generating OAuth Secret..."

# नवीन CLI नुसार कमांड बदलली आहे: service-principal-secrets
SECRET_JSON=$(databricks service-principal-secrets create "$SPN_ID" --output json)

# नवीन CLI मध्ये 'secret' की असते
CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.secret // .client_secret')

if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" == "null" ]; then
    echo "❌ Error: Secret जनरेट होऊ शकले नाही. कदाचित परवानग्या कमी आहेत."
    exit 1
fi

echo "✅ OAuth secret generated successfully"

echo "🚀 Step 4: Storing in Azure Key Vault: $KV_NAME"
# Key Vault मध्ये सेव्ह करणे
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-id" --value "$CLIENT_ID" --output none
az keyvault secret set --vault-name "$KV_NAME" --name "${SPN_DISPLAY_NAME}-secret" --value "$CLIENT_SECRET" --output none

echo "----------------------------------------------------"
echo "🎉 SUCCESS! सर्व स्टेप्स पूर्ण झाल्या आहेत."
echo "SPN: $SPN_DISPLAY_NAME"
echo "ID: $SPN_ID"
echo "----------------------------------------------------"
