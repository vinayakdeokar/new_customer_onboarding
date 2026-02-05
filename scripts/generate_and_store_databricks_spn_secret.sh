#!/bin/bash
set -e

SPN_DISPLAY_NAME=$1

if [ -z "$SPN_DISPLAY_NAME" ]; then echo "❌ SPN name missing"; exit 1; fi

echo "🔐 Step 1: Login Check"
databricks clusters list --page-size 1 > /dev/null
echo "✅ Login OK"

echo "🔎 Step 2: Directly fetching ID for '$SPN_DISPLAY_NAME'..."

# फिल्टर वापरून थेट त्या नावाचा ID मिळवणे (ही कमांड १०० SPN असले तरी फक्त एकाचाच डेटा आणेल)
SPN_ID=$(databricks service-principals list --filter "display_name eq '$SPN_DISPLAY_NAME'" --output json | jq -r '
  if type=="array" then .[0].id 
  elif .service_principals then .service_principals[0].id 
  else empty end
')

if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
    echo "❌ Error: '$SPN_DISPLAY_NAME' नावाचा SPN सापडला नाही. कृपया नाव तपासा."
    exit 1
fi

echo "✅ Found SPN ID: $SPN_ID"

echo "🔐 Step 3: Generating OAuth Secret..."
# ३. सिक्रेट जनरेट करणे (थेट त्या ID साठी)
SECRET_JSON=$(databricks service-principals secrets create "$SPN_ID" --output json)

CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.client_id')
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
echo "ID: $SPN_ID"
echo "----------------------------------------------------"
