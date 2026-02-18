#!/bin/bash
set -e

#########################################
# INPUT PARAMETERS
#########################################

CUSTOMER_CODE=$1
PRODUCT=$2
ENV=$3

#########################################
# FAB CLI PATH
#########################################

FAB="$(pwd)/fabricenv/bin/fab"

if [ ! -f "$FAB" ]; then
  echo "❌ Fabric CLI not found at $FAB"
  exit 1
fi

#########################################
# FIX FOR JENKINS (Token Storage)
#########################################

export HOME=$(pwd)
export FABRIC_CONFIG_DIR="$HOME/.fabric"
mkdir -p "$FABRIC_CONFIG_DIR"

$FAB config set encryption_fallback_enabled true

#########################################
# WORKSPACE NAME
#########################################

WORKSPACE_NAME="ws-${CUSTOMER_CODE}-${PRODUCT}-${ENV}-001"

echo "========================================="
echo "🚀 Creating Fabric Workspace"
echo "Workspace Name: $WORKSPACE_NAME"
echo "========================================="

#########################################
# LOGIN
#########################################

$FAB auth logout >/dev/null 2>&1 || true

$FAB auth login \
  -u "$FABRIC_CLIENT_ID" \
  -p "$FABRIC_CLIENT_SECRET" \
  --tenant "$FABRIC_TENANT_ID"

$FAB auth status

#########################################
# CHECK IF WORKSPACE EXISTS
#########################################

EXISTING_ID=$($FAB api workspaces -A fabric | jq -r '
  if .value then
    .value[] | select(.displayName=="'"$WORKSPACE_NAME"'") | .id
  else
    .text.value[] | select(.displayName=="'"$WORKSPACE_NAME"'") | .id
  end
')

if [ -n "$EXISTING_ID" ]; then
  echo "⚠ Workspace already exists. Skipping creation."
  echo "Workspace ID: $EXISTING_ID"
  exit 0
fi

#########################################
# CREATE PAYLOAD
#########################################

cat <<EOF > workspace.json
{
  "displayName": "${WORKSPACE_NAME}",
  "capacityObjectId": "9c15d8dc-a072-4186-9b42-875d52497dbe",
  "datasetStorageMode": 1,
  "isServiceApp": false
}
EOF

#########################################
# CREATE WORKSPACE
#########################################

RESPONSE=$($FAB api workspaces -A fabric -X post -i workspace.json)

echo "API RESPONSE:"
echo "$RESPONSE"

NEW_ID=$(echo "$RESPONSE" | jq -r '.id // .text.id')

if [ "$NEW_ID" = "null" ] || [ -z "$NEW_ID" ]; then
  echo "❌ Workspace creation failed"
  exit 1
fi

echo "========================================="
echo "✅ Workspace Created Successfully"
echo "Workspace ID: $NEW_ID"
echo "========================================="

#########################################
# ADD USER TO WORKSPACE (VISIBLE IN UI)
#########################################


USER_OBJECT_ID="35fd6b80-ba4a-462c-adc4-e7c8d2755995"

cat > role.json <<EOF
{
  "principal": {
    "id": "${USER_OBJECT_ID}",
    "type": "User"
  },
  "role": "Admin"
}
EOF

$FAB api workspaces/${NEW_ID}/roleAssignments \
  -A fabric -X post -i role.json

echo "✅ User assigned as Admin to workspace"
