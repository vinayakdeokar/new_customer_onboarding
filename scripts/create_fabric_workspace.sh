#!/bin/bash
set -e

CUSTOMER_CODE=$1
PRODUCT=$2
ENV=$3

FAB="$(pwd)/fabricenv/bin/fab"

if [ ! -f "$FAB" ]; then
  echo "❌ Fabric CLI not found at $FAB"
  exit 1
fi

WORKSPACE_NAME="ws-${CUSTOMER_CODE}-${PRODUCT}-${ENV}-001"


echo "========================================="
echo "🚀 Creating Fabric Workspace"
echo "Workspace Name: $WORKSPACE_NAME"
echo "========================================="

# Login to Fabric
$FAB auth login \
  -u "$FABRIC_CLIENT_ID" \
  -p "$FABRIC_CLIENT_SECRET" \
  --tenant "$FABRIC_TENANT_ID" >/dev/null 2>&1

# Check if workspace exists
EXISTING_ID=$($FAB api workspaces -A fabric | jq -r '
  if .value then
    .value[] | select(.displayName=="'"$WORKSPACE_NAME"'") | .id
  else
    .text.value[] | select(.displayName=="'"$WORKSPACE_NAME"'") | .id
  end
')

if [ -n "$EXISTING_ID" ]; then
  echo "⚠ Workspace already exists. Skipping creation."
  exit 0
fi

# Create workspace
RESPONSE=$($FAB api workspaces -A fabric -X post -i workspace.json)

echo "API RESPONSE:"
echo "$RESPONSE"

NEW_ID=$(echo "$RESPONSE" | jq -r '.id // .text.id')

if [ "$NEW_ID" = "null" ] || [ -z "$NEW_ID" ]; then
  echo "❌ Workspace creation failed"
  exit 1
fi

echo "✅ Workspace Created Successfully"
echo "Workspace ID: $NEW_ID"
echo "========================================="

# #!/bin/bash
# set -e

# CUSTOMER_CODE=$1
# PRODUCT=$2
# ENV=$3

# FAB="$WORKSPACE/fabricenv/bin/fab"

# WORKSPACE_NAME="ws-${CUSTOMER_CODE}-${PRODUCT}-${ENV}-001"

# echo "========================================="
# echo "🚀 Creating Fabric Workspace"
# echo "Workspace Name: $WORKSPACE_NAME"
# echo "========================================="

# # Login to Fabric
# $FAB auth login \
#   -u "$FABRIC_CLIENT_ID" \
#   -p "$FABRIC_CLIENT_SECRET" \
#   --tenant "$FABRIC_TENANT_ID" >/dev/null 2>&1

# echo "API RESPONSE:"
# echo "$RESPONSE"


# # Check if workspace exists
# EXISTING_ID=$($FAB api workspaces -A fabric | \
# jq -r --arg name "$WORKSPACE_NAME" '.text.value[]? | select(.displayName==$name) | .id')

# if [ -n "$EXISTING_ID" ]; then
#   echo "⚠ Workspace already exists. Skipping creation."
#   exit 0
# fi

# # Create workspace payload
# cat <<EOF > workspace.json
# {
#   "displayName": "${WORKSPACE_NAME}",
#   "capacityObjectId": "9c15d8dc-a072-4186-9b42-875d52497dbe",
#   "datasetStorageMode": 1,
#   "isServiceApp": false
# }
# EOF

# RESPONSE=$($FAB api workspaces -A fabric -X post -i workspace.json)
# NEW_ID=$(echo "$RESPONSE" | jq -r '.text.id')

# if [ -z "$NEW_ID" ]; then
#   echo "❌ Workspace creation failed"
#   exit 1
# fi

# echo "✅ Workspace Created Successfully"
# echo "Workspace ID: $NEW_ID"
# echo "========================================="
