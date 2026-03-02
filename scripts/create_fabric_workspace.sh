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
echo " Creating Fabric Workspace"
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
  echo "Workspace already exists. Skipping creation."
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
#echo "$RESPONSE"

NEW_ID=$(echo "$RESPONSE" | jq -r '.id // .text.id')

if [ "$NEW_ID" = "null" ] || [ -z "$NEW_ID" ]; then
  echo " Workspace creation failed"
  exit 1
fi

echo "========================================="
echo " Workspace Created Successfully"
#echo "Workspace ID: $NEW_ID"
echo "========================================="

#########################################
# BUILD DYNAMIC GROUP NAMES
#########################################

GROUP_PBI_ADMIN_NAME="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-admin-internal-qa"
GROUP_PBI_CONTR_EXT_NAME="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-contributor-external-qa"
GROUP_PBI_CONTR_INT_NAME="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-contributor-internal-qa"
GROUP_PBI_VIEWER_INT_NAME="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-viewer-internal-qa"
GROUP_PBI_VIEWER_EXT_NAME="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-viewer-external-qa"

# GROUP_PBI_ADMIN="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-admin-internal-qa"
# GROUP_PBI_CONTR_EXT="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-contributor-external-qa"
# GROUP_PBI_CONTR_INT="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-contributor-internal-qa"
# GROUP_PBI_VIEWER_INT="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-viewer-internal-qa"
# GROUP_PBI_VIEWER_EXT="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-viewer-external-qa"


echo "Admin Group: $GROUP_PBI_ADMIN_NAME"
echo "Contributor External: $GROUP_PBI_CONTR_EXT_NAME"
echo "Contributor Internal: $GROUP_PBI_CONTR_INT_NAME"
echo "Viewer Internal: $GROUP_PBI_VIEWER_INT_NAME"
echo "Viewer External: $GROUP_PBI_VIEWER_EXT_NAME"


#########################################
# FETCH GROUP OBJECT IDs FROM AZURE AD
#########################################

GROUP_PBI_ADMIN=$(az ad group list --query "[?displayName=='$GROUP_PBI_ADMIN_NAME'].id" -o tsv)
GROUP_PBI_CONTR_EXT=$(az ad group list --query "[?displayName=='$GROUP_PBI_CONTR_EXT_NAME'].id" -o tsv)
GROUP_PBI_CONTR_INT=$(az ad group list --query "[?displayName=='$GROUP_PBI_CONTR_INT_NAME'].id" -o tsv)
GROUP_PBI_VIEWER_INT=$(az ad group list --query "[?displayName=='$GROUP_PBI_VIEWER_INT_NAME'].id" -o tsv)
GROUP_PBI_VIEWER_EXT=$(az ad group list --query "[?displayName=='$GROUP_PBI_VIEWER_EXT_NAME'].id" -o tsv)



#########################################
# VALIDATE GROUPS
#########################################

if [ -z "$GROUP_PBI_ADMIN" ] || [ -z "$GROUP_PBI_CONTR_EXT" ] || [ -z "$GROUP_PBI_CONTR_INT" ] || \
   [ -z "$GROUP_PBI_VIEWER_INT" ] || [ -z "$GROUP_PBI_VIEWER_EXT" ]; then
  echo " One or more groups not found in Azure AD. Exiting."
  exit 1
fi



echo " All groups found in Azure AD"

#########################################
# MAP NAME → ID
#########################################

declare -A GROUP_ROLE_MAP

GROUP_ROLE_MAP[$GROUP_PBI_ADMIN]="Admin"
GROUP_ROLE_MAP[$GROUP_PBI_CONTR_EXT]="Contributor"
GROUP_ROLE_MAP[$GROUP_PBI_CONTR_INT]="Contributor"
GROUP_ROLE_MAP[$GROUP_PBI_VIEWER_INT]="Viewer"
GROUP_ROLE_MAP[$GROUP_PBI_VIEWER_EXT]="Viewer"



#########################################
# ASSIGN GROUPS TO FABRIC CONNECTION
#########################################

for GROUP_ID in "${!GROUP_ROLE_MAP[@]}"
do
  ROLE=${GROUP_ROLE_MAP[$GROUP_ID]}

  cat > role.json <<EOF
{
  "principal": {
    "id": "${GROUP_ID}",
    "type": "Group"
  },
  "role": "${ROLE}"
}
EOF

  $FAB api workspaces/${NEW_ID}/roleAssignments \
    -A fabric -X post -i role.json

  echo "Assigned ${ROLE} to ${GROUP_ID}"
done

# echo "========================================="
# echo " All Dynamic Groups Assigned Successfully"
# echo "========================================="
# #!/bin/bash
# set -e

# #########################################
# # INPUT PARAMETERS
# #########################################

# CUSTOMER_CODE=$1
# PRODUCT=$2
# ENV=$3

# #########################################
# # FAB CLI PATH
# #########################################

# FAB="$(pwd)/fabricenv/bin/fab"

# if [ ! -f "$FAB" ]; then
#   echo "❌ Fabric CLI not found at $FAB"
#   exit 1
# fi

# #########################################
# # FIX FOR JENKINS (Token Storage)
# #########################################

# export HOME=$(pwd)
# export FABRIC_CONFIG_DIR="$HOME/.fabric"
# mkdir -p "$FABRIC_CONFIG_DIR"

# $FAB config set encryption_fallback_enabled true

# #########################################
# # WORKSPACE NAME
# #########################################

# WORKSPACE_NAME="ws-${CUSTOMER_CODE}-${PRODUCT}-${ENV}-001"

# echo "========================================="
# echo "🚀 Creating Fabric Workspace"
# echo "Workspace Name: $WORKSPACE_NAME"
# echo "========================================="

# #########################################
# # LOGIN
# #########################################

# $FAB auth logout >/dev/null 2>&1 || true

# $FAB auth login \
#   -u "$FABRIC_CLIENT_ID" \
#   -p "$FABRIC_CLIENT_SECRET" \
#   --tenant "$FABRIC_TENANT_ID"

# $FAB auth status

# #########################################
# # CHECK IF WORKSPACE EXISTS
# #########################################

# EXISTING_ID=$($FAB api workspaces -A fabric | jq -r '
#   if .value then
#     .value[] | select(.displayName=="'"$WORKSPACE_NAME"'") | .id
#   else
#     .text.value[] | select(.displayName=="'"$WORKSPACE_NAME"'") | .id
#   end
# ')

# if [ -n "$EXISTING_ID" ]; then
#   echo "⚠ Workspace already exists. Skipping creation."
#   echo "Workspace ID: $EXISTING_ID"
#   exit 0
# fi

# #########################################
# # CREATE PAYLOAD
# #########################################

# cat <<EOF > workspace.json
# {
#   "displayName": "${WORKSPACE_NAME}",
#   "capacityObjectId": "9c15d8dc-a072-4186-9b42-875d52497dbe",
#   "datasetStorageMode": 1,
#   "isServiceApp": false
# }
# EOF

# #########################################
# # CREATE WORKSPACE
# #########################################

# RESPONSE=$($FAB api workspaces -A fabric -X post -i workspace.json)

# echo "API RESPONSE:"
# echo "$RESPONSE"

# NEW_ID=$(echo "$RESPONSE" | jq -r '.id // .text.id')

# if [ "$NEW_ID" = "null" ] || [ -z "$NEW_ID" ]; then
#   echo "❌ Workspace creation failed"
#   exit 1
# fi

# echo "========================================="
# echo "✅ Workspace Created Successfully"
# echo "Workspace ID: $NEW_ID"
# echo "========================================="

# #########################################
# # ADD USER TO WORKSPACE (VISIBLE IN UI)
# #########################################


# USER_OBJECT_ID="35fd6b80-ba4a-462c-adc4-e7c8d2755995"

# cat > role.json <<EOF
# {
#   "principal": {
#     "id": "${USER_OBJECT_ID}",
#     "type": "User"
#   },
#   "role": "Admin"
# }
# EOF

# $FAB api workspaces/${NEW_ID}/roleAssignments \
#   -A fabric -X post -i role.json

# echo "✅ User assigned as Admin to workspace"
