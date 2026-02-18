#!/bin/bash
set -ex

FAB="$(pwd)/fabricenv/bin/fab"

if [ ! -f "$FAB" ]; then
  echo "❌ Fabric CLI not found at $FAB"
  exit 1
fi

set -e

FAB="$WORKSPACE/fabricenv/bin/fab"


TENANT_ID="$FABRIC_TENANT_ID"
AUTOMATION_CLIENT_ID="$FABRIC_CLIENT_ID"
AUTOMATION_CLIENT_SECRET="$FABRIC_CLIENT_SECRET"


if [ -z "$AUTOMATION_CLIENT_ID" ] || [ -z "$AUTOMATION_CLIENT_SECRET" ] || [ -z "$TENANT_ID" ]; then
  echo "❌ Fabric credentials not provided from pipeline"
  exit 1
fi


DISPLAY_NAME="db-vnet-${ENV}-${CUSTOMER_CODE}"
GATEWAY_ID="34377033-6f6f-433a-9a66-3095e996f65c"

DATABRICKS_HOST="adb-7405618110977329.9.azuredatabricks.net"
HTTP_PATH="/sql/1.0/warehouses/334a2ae248719051"

 SECRET_CLIENT_ID_NAME="sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id"
 SECRET_SECRET_NAME="sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret"


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
#$FAB auth status

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


if [ -z "$GATEWAY_ID" ]; then
  echo "❌ Gateway not found!"
  exit 1
fi

#echo "✅ Gateway ID: $GATEWAY_ID"


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

if $FAB api connections -A fabric -X post -i payload.json > /dev/null 2>&1; then
    echo "✅ VNet Connection Created Successfully"
else
    echo "❌ VNet Connection Creation Failed"
    exit 1
fi

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





echo "========================================="
echo "🚀 Assigning 3 AAD Groups as USER"
#echo "Connection: $CONNECTION_ID"
echo "========================================="




#########################################
# BUILD DYNAMIC GROUP NAMES
#########################################

GROUP_ADMIN="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-admin-internal-qa"
GROUP_CONTR_EXT="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-contributor-external-qa"
GROUP_CONTR_INT="agd-${CUSTOMER_CODE}-${PRODUCT}-powerbi-contributor-internal-qa"

echo "Admin Group: $GROUP_ADMIN"
echo "Contributor External: $GROUP_CONTR_EXT"
echo "Contributor Internal: $GROUP_CONTR_INT"

echo "Contributor Internal: $GROUP_CONTR_INT"



#########################################
# FETCH GROUP OBJECT IDs FROM AZURE AD
#########################################

GROUP1=$(az ad group list --query "[?contains(displayName, '$GROUP_ADMIN')].id" -o tsv)
GROUP2=$(az ad group list --query "[?contains(displayName, '$GROUP_CONTR_EXT')].id" -o tsv)
GROUP3=$(az ad group list --query "[?contains(displayName, '$GROUP_CONTR_INT')].id" -o tsv)

#########################################
# VALIDATE GROUPS
#########################################

if [ -z "$GROUP1" ] || [ -z "$GROUP2" ] || [ -z "$GROUP3" ]; then
  echo "❌ One or more groups not found in Azure AD. Exiting."
  exit 1
fi

echo "✅ All groups found in Azure AD"

#########################################
# MAP NAME → ID
#########################################

declare -A GROUP_MAP
GROUP_MAP["$GROUP_ADMIN"]=$GROUP1
GROUP_MAP["$GROUP_CONTR_EXT"]=$GROUP2
GROUP_MAP["$GROUP_CONTR_INT"]=$GROUP3

#########################################
# ASSIGN GROUPS TO FABRIC CONNECTION
#########################################

for GROUP_NAME in "${!GROUP_MAP[@]}"
do
  GROUP_ID=${GROUP_MAP[$GROUP_NAME]}

  cat > role.json <<EOF
{
  "principal": {
    "id": "${GROUP_ID}",
    "type": "Group"
  },
  "role": "User"
}
EOF

  echo "➕ Assigning Group: $GROUP_NAME"

  $FAB api connections/${CONNECTION_ID}/roleAssignments \
    -A fabric -X post -i role.json > /dev/null 2>&1


  echo "✅ Assigned: $GROUP_NAME"
done

echo "========================================="
echo "🎉 All Dynamic Groups Assigned Successfully"
echo "========================================="
