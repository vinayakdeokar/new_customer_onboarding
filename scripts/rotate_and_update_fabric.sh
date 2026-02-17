#!/bin/bash
set -e

FAB="$WORKSPACE/fabricenv/bin/fab"

echo "========================================="
echo "🔄 Starting SPN Secret Rotation"
echo "========================================="

#########################################
# 1️⃣ Generate New Secret in Databricks
#########################################

NEW_SECRET=$(scripts/dbx_generate_new_secret.sh)

if [ -z "$NEW_SECRET" ]; then
  echo "❌ Secret generation failed"
  exit 1
fi

echo "✅ New Secret Generated"

#########################################
# 2️⃣ Store in Key Vault
#########################################

az keyvault secret set \
  --vault-name $KV_NAME \
  --name "${SPN_NAME}-secret" \
  --value "$NEW_SECRET" >/dev/null

echo "✅ Key Vault Updated"

#########################################
# 3️⃣ Get Fabric Connection ID
#########################################

CONNECTION_NAME="db-vnet-${ENV}-${CUSTOMER_CODE}"

CONNECTION_ID=$($FAB api connections -A fabric | \
jq -r --arg name "$CONNECTION_NAME" '.text.value[]? | select(.displayName==$name) | .id')

if [ -z "$CONNECTION_ID" ]; then
  echo "❌ Fabric Connection not found"
  exit 1
fi

echo "✅ Fabric Connection Found"

#########################################
# 4️⃣ PATCH Credentials Only
#########################################

cat > update.json <<EOF
{
  "credentialDetails": {
    "singleSignOnType": "None",
    "credentials": {
      "credentialType": "Basic",
      "username": "${SPN_CLIENT_ID_KV}",
      "password": "${NEW_SECRET}"
    }
  }
}
EOF

$FAB api connections/$CONNECTION_ID \
  -A fabric \
  -X patch \
  -i update.json >/dev/null

echo "========================================="
echo "🎉 Fabric Credentials Rotated Successfully"
echo "========================================="
