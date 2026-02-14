#!/bin/bash
set -e

FAB="$WORKSPACE/fabricenv/bin/fab"

# =========================
# HARD CODE VALUES
# =========================

TENANT_ID="6fbff720-d89b-4675-b188-48491f24b460"

AUTOMATION_CLIENT_ID="5edcfcf8-9dbd-4c1b-a602-a0887f677e2e"
AUTOMATION_CLIENT_SECRET="O8W8Q~5W.ato3IN3L3QdEDWberZzOSp7.VObIdp3"

#DISPLAY_NAME="db-vnet-hardcode-test-2"
DISPLAY_NAME="db-vnet-${ENV}-${CUSTOMER_CODE}"

GATEWAY_ID="34377033-6f6f-433a-9a66-3095e996f65c"

DATABRICKS_HOST="adb-7405618110977329.9.azuredatabricks.net"
HTTP_PATH="/sql/1.0/warehouses/334a2ae248719051"



SECRET_CLIENT_ID_NAME="sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id"
SECRET_SECRET_NAME="sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret"

# CUSTOMER_SP_CLIENT_ID="842439d6-518c-42a5-af01-c492d638c6c9"
# CUSTOMER_SP_SECRET="dose0c1fbea254834971a344988f49687236"

# =========================
# LOGIN
# =========================

echo "🔐 Fabric Login..."

$FAB config set encryption_fallback_enabled true

$FAB auth login \
  -u $AUTOMATION_CLIENT_ID \
  -p $AUTOMATION_CLIENT_SECRET \
  --tenant $TENANT_ID

echo "✅ Login Successful"
$FAB auth status

# =========================
# AZURE LOGIN (for Key Vault)
# =========================

echo "🔐 Azure Login for Key Vault..."

az login --service-principal \
  -u $AUTOMATION_CLIENT_ID \
  -p $AUTOMATION_CLIENT_SECRET \
  --tenant $TENANT_ID >/dev/null

echo "✅ Azure Login Successful"

echo "🔎 Fetching Gateway ID dynamically..."

GATEWAY_ID=$($FAB api gateways -A fabric | \
jq -r '.text.value[]? | select(.displayName=="vnwt-db-fab-fabric-sub") | .id')


# GATEWAY_ID=$($FAB api virtualNetworkGateways -A fabric | \
# jq -r '.text.value[] | select(.displayName=="vnwt-db-fab-fabric-sub") | .id')

if [ -z "$GATEWAY_ID" ]; then
  echo "❌ Gateway not found!"
  exit 1
fi

echo "✅ Gateway ID: $GATEWAY_ID"


# =========================
# FETCH CUSTOMER SPN FROM KEY VAULT
# =========================

echo "🔎 Fetching Customer SPN from Key Vault..."

CUSTOMER_SP_CLIENT_ID=$(az keyvault secret show \
  --vault-name kv-databricks-fab \
  --name $SECRET_CLIENT_ID_NAME \
  --query value -o tsv)

CUSTOMER_SP_SECRET=$(az keyvault secret show \
  --vault-name kv-databricks-fab \
  --name $SECRET_SECRET_NAME \
  --query value -o tsv)

echo "✅ Secrets Fetched Successfully"
echo "CLIENT_ID = $CUSTOMER_SP_CLIENT_ID"
echo "SECRET LENGTH = ${#CUSTOMER_SP_SECRET}"



# =========================
# CREATE CONNECTION
# =========================

echo "🚀 Creating VNet Connection..."

cat > payload.json <<EOF
{
  "displayName": "${DISPLAY_NAME}",
  "connectivityType": "VirtualNetworkGateway",
  "gatewayId": "${GATEWAY_ID}",
  "privacyLevel": "Private",
  "connectionDetails": {
    "type": "Databricks",
    "creationMethod": "Databricks.Catalogs",
    "parameters": [
      {
        "dataType": "Text",
        "name": "host",
        "value": "${DATABRICKS_HOST}"
      },
      {
        "dataType": "Text",
        "name": "httpPath",
        "value": "${HTTP_PATH}"
      }
    ]
  },
  "credentialDetails": {
    "credentialType": "Basic",
    "singleSignOnType": "None",
    "connectionEncryption": "NotEncrypted",
    "skipTestConnection": false,
    "credentials": {
      "credentialType": "Basic",
      "username": "${CUSTOMER_SP_CLIENT_ID}",
      "password": "${CUSTOMER_SP_SECRET}"



    }
  }
}
EOF



# cat > payload.json <<EOF
# {
#   "displayName": "${DISPLAY_NAME}",
#   "connectivityType": "VirtualNetworkGateway",
#   "gatewayId": "${GATEWAY_ID}",
#   "privacyLevel": "Private",
#   "connectionDetails": {
#     "type": "Databricks",
#     "creationMethod": "Databricks.Catalogs",
#     "parameters": [
#       {
#         "dataType": "Text",
#         "name": "host",
#         "value": "${DATABRICKS_HOST}"
#       },
#       {
#         "dataType": "Text",
#         "name": "httpPath",
#         "value": "${HTTP_PATH}"
#       }
#     ]
#   },
#    "credentialDetails": {
#      "credentialType": "Basic",
#      "singleSignOnType": "None",
#      "connectionEncryption": "NotEncrypted",
#      "skipTestConnection": false,
#      "credentials": {
#        "credentialType": "Basic",
#        "username": "${CUSTOMER_SP_CLIENT_ID}",
#        "password": "${CUSTOMER_SP_SECRET}"
#      }
#    }
# }
# EOF



$FAB api connections -A fabric -X post -i payload.json

echo "================================="
echo "✅ DONE"
echo "================================="

#!/bin/bash
set -e

FAB_CMD="$WORKSPACE/fabricenv/bin/fab"

#CONNECTION_ID="a8b22aa5-ad59-4094-a5ce-535a6196df65"
CONNECTION_ID=$($FAB api connections -A fabric | \
jq -r '.text.value[]? | select(.displayName=="'"${DISPLAY_NAME}"'") | .id')

if [ -z "$CONNECTION_ID" ]; then
  echo "❌ Connection ID not found"
  exit 1
fi

<-- your created connection id

echo "========================================="
echo "🚀 Assigning 3 AAD Groups as USER"
echo "Connection: $CONNECTION_ID"
echo "========================================="

#########################################
# Fabric Login (Automation SPN)
#########################################

# $FAB_CMD config set encryption_fallback_enabled true

# $FAB_CMD auth login \
#   -u 5edcfcf8-9dbd-4c1b-a602-a0887f677e2e \
#   -p '3iH8Q~kqNjz4SgqvKW~JsoXdRPbdCSqTYGLYZai4' \
#   --tenant 6fbff720-d89b-4675-b188-48491f24b460

# echo "✅ Login Successful"

#########################################
# GROUP OBJECT IDs (Azure AD)
#########################################

GROUP1="883140c6-51f1-4d9f-8efa-96161d175026"
GROUP2="89781bdf-bd4d-4da3-9e42-fa14c5cecb49"
GROUP3="badb555e-db90-46c3-b199-e33eb1a662b1"

#########################################
# Function to Add Group as USER
#########################################

add_group() {

  GROUP_ID=$1

  cat > role.json <<EOF
{
  "principal": {
    "id": "${GROUP_ID}",
    "type": "Group"
  },
  "role": "User"
}
EOF

  echo "➕ Adding Group $GROUP_ID as USER"

  
  #$FAB_CMD api connections/${CONNECTION_ID}/roleAssignments
  $FAB api connections/${CONNECTION_ID}/roleAssignments \
    -A fabric -X post -i role.json

  echo "✅ Done"
}

#########################################
# Add All 3 Groups
#########################################

add_group $GROUP1
add_group $GROUP2
add_group $GROUP3

echo "========================================="
echo "🎉 All Groups Assigned as USER"
echo "========================================="


