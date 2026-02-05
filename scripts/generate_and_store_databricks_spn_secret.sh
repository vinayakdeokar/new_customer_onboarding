#!/bin/bash
set -e

# Arguments आणि Environment Variables चेक करणे
SPN_DISPLAY_NAME=$1

if [ -z "$SPN_DISPLAY_NAME" ]; then
  echo "❌ Error: SPN display name missing (Pass as first argument)"
  exit 1
fi

if [ -z "$KV_NAME" ]; then
  echo "❌ Error: KV_NAME environment variable is missing"
  exit 1
fi

echo "🔐 Step 1: Verify Databricks CLI login"
# जर लॉगिन नसेल तर ही कमांड फेल होईल
databricks clusters list --max-results 1 > /dev/null
echo "✅ Databricks CLI login OK"

echo "🔎 Step 2: Resolve Databricks SPN ID for: $SPN_DISPLAY_NAME"

# सर्व SPNs ची लिस्ट काढणे
RAW_JSON=$(databricks service-principals list --output json)

# जर आऊटपुट पूर्णपणे रिकामे किंवा null असेल तर परवानग्या तपासाव्या लागतील
if [ -z "$RAW_JSON" ] || [ "$RAW_JSON" == "null" ]; then
  echo "❌ Error: Could not fetch service principals list. Please check if your token has Admin access."
  exit 1
fi

# नाव मॅच करून ID शोधणे (Old आणि New CLI दोन्हीसाठी सुसंगत)
SPN_ID=$(echo "$RAW_JSON" | jq -r --arg NAME "$SPN_DISPLAY_NAME" '
  if (.service_principals | type == "array") then
    .service_principals[] | select(.display_name == $NAME) | .id
  elif (type == "array") then
    .[] | select(.display_name == $NAME) | .id
  else
    empty
  end
' | head -n 1)

# जर SPN_ID सापडला नाही तर
if [ -z "$SPN_ID" ] || [ "$SPN_ID" == "null" ]; then
  echo "❌ SPN not found in Databricks: $SPN_DISPLAY_NAME"
  echo "--- Available SPNs in this Workspace ---"
  echo "$RAW_JSON" | jq -r 'if .service_principals then .service_principals[].display_name else .[].display_name end' || echo "No display names found."
  exit 1
fi

echo "✅ SPN ID resolved: $SPN_ID"

echo "🔐 Step 3: Generate OAuth secret using Databricks CLI"

# गुपित (Secret) तयार करणे
SECRET_JSON=$(databricks service-principals secrets create "$SPN_ID" --output json)

OAUTH_CLIENT_ID=$(echo "$SECRET_JSON" | jq -r '.client_id')
OAUTH_CLIENT_SECRET=$(echo "$SECRET_JSON" | jq -r '.client_secret')

if [ -z "$OAUTH_CLIENT_SECRET" ] || [ "$OAUTH_CLIENT_SECRET" == "null" ]; then
  echo "❌ OAuth secret generation failed. The SPN might already have a secret or lacks permissions."
  exit 1
fi

echo "✅ OAuth secret generated successfully"

echo "🔐 Step 4: Store secrets in Azure Key Vault: $KV_NAME"

# Azure Key Vault मध्ये Client ID स्टोअर करणे
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${SPN_DISPLAY_NAME}-dbx-client-id" \
  --value "$OAUTH_CLIENT_ID" \
  --output none

# Azure Key Vault मध्ये Secret स्टोअर करणे
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${SPN_DISPLAY_NAME}-dbx-client-secret" \
  --value "$OAUTH_CLIENT_SECRET" \
  --output none

echo "--------------------------------------------------------"
echo "🎉 SUCCESS: Secrets stored in Key Vault!"
echo "Client ID Name: ${SPN_DISPLAY_NAME}-dbx-client-id"
echo "Secret Name: ${SPN_DISPLAY_NAME}-dbx-client-secret"
echo "--------------------------------------------------------"
