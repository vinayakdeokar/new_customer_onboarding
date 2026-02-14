#!/bin/bash
set -e

FAB="$WORKSPACE/fabricenv/bin/fab"

# =========================
# HARD CODE VALUES
# =========================

TENANT_ID="6bff720-089b-4675-b188-48491f24b460"

AUTOMATION_CLIENT_ID="5edcfcf8-9dbd-4c1b-a602-a0887f677e2e"
AUTOMATION_CLIENT_SECRET="O8W8Q~5W.ato3IN3L3QdEDWberZzOSp7.VObIdp3"

DISPLAY_NAME="db-vnet-hardcode-test"

GATEWAY_ID="34377033-6f6f-433a-9a66-3095e996f65c"

DATABRICKS_HOST="adb-7405609173671370.10.azuredatabricks.net"
HTTP_PATH="/sql/1.0/warehouses/559747c78f71249c"

CUSTOMER_SP_CLIENT_ID="842439d6-518c-42a5-af01-c492d638c6c9"
CUSTOMER_SP_SECRET="dose0c1fbea254834971a344988f49687236"

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

$FAB api connections -A fabric -X post -i payload.json

echo "================================="
echo "✅ DONE"
echo "================================="

# #!/bin/bash
# set -e

# FAB_CMD="$WORKSPACE/fabricenv/bin/fab"

# echo "============================================"
# echo "🚀 FABRIC VNET CONNECTION AUTOMATION STARTED"
# echo "Customer: $CUSTOMER_CODE"
# echo "============================================"

# echo "Using FAB from:"
# ls -l $FAB_CMD

# ############################################
# # VARIABLES
# ############################################

# DISPLAY_NAME="db-vnet-${CUSTOMER_CODE}"
# GATEWAY_ID="34377033-6f6f-433a-9a66-3095e996f65c"
# HTTP_PATH="/sql/1.0/warehouses/${DATABRICKS_SQL_WAREHOUSE_ID}"

# ############################################
# # 1️⃣ Fabric Login
# ############################################

# echo "🔐 Configuring Fabric CLI for CI..."

# $FAB_CMD config set encryption_fallback_enabled true

# echo "🔐 Logging into Fabric..."

# $FAB_CMD auth login \
#   -u $FABRIC_CLIENT_ID \
#   -p $FABRIC_CLIENT_SECRET \
#   --tenant $FABRIC_TENANT_ID 

# echo "✅ Fabric login successful"
# # echo "=== LIST WORKSPACES VISIBLE TO SPN ==="
# # $FAB_CMD api groups -A fabric


# #!/bin/bash
# set -e

# FAB_CMD="$WORKSPACE/fabricenv/bin/fab"

# echo "============================================"
# echo "🚀 FABRIC VNET HARD-CODE TEST"
# echo "============================================"

# ############################################
# # 1️⃣ Fabric Login (Automation SPN)
# ############################################

# $FAB_CMD config set encryption_fallback_enabled true

# $FAB_CMD auth login \
#   -u "<AUTOMATION_SPn_CLIENT_ID>" \
#   -p "<AUTOMATION_SPn_CLIENT_SECRET>" \
#   --tenant "<TENANT_ID>"

# echo "✅ Logged into Fabric"

# ############################################
# # 2️⃣ Create Connection (Hardcoded Values)
# ############################################

# cat > payload.json <<EOF
# {
#   "displayName": "db-vnet-hardcode-test",
#   "connectivityType": "VirtualNetworkGateway",
#   "gatewayId": "34377033-6f6f-433a-9a66-3095e996f65c",
#   "privacyLevel": "Private",
#   "connectionDetails": {
#     "type": "Databricks",
#     "creationMethod": "Databricks.Catalogs",
#     "parameters": [
#       {
#         "dataType": "Text",
#         "name": "host",
#         "value": "adb-7405609173671370.10.azuredatabricks.net"
#       },
#       {
#         "dataType": "Text",
#         "name": "httpPath",
#         "value": "/sql/1.0/warehouses/559747c78f71249c"
#       }
#     ]
#   },
#   "credentialDetails": {
#     "credentialType": "Basic",
#     "singleSignOnType": "None",
#     "connectionEncryption": "NotEncrypted",
#     "skipTestConnection": false,
#     "credentials": {
#       "credentialType": "Basic",
#       "username": "842439d6-518c-42a5-af01-c492d638c6c9",
#       "password": "dose0c1fbea254834971a344988f49687236"
#     }
#   }
# }
# EOF

# RESPONSE=$($FAB_CMD api connections -A fabric -X post -i payload.json)

# echo "==== CREATE RESPONSE ===="
# echo "$RESPONSE"
# echo "========================="

# ############################################
# # 3️⃣ Fetch Connection ID
# ############################################

# CONNECTION_ID=$($FAB_CMD api connections -A fabric | \
#   jq -r '.text.value[]? | select(.displayName=="db-vnet-hardcode-test") | .id')

# echo "Connection ID: $CONNECTION_ID"

# ############################################
# # 4️⃣ Assign Group Owner (Hardcoded Group)
# ############################################

# cat > role.json <<EOF
# {
#   "principal": {
#     "id": "04ee87bd-1b24-4c08-88e8-7ceb037fdd6a",
#     "type": "Group"
#   },
#   "role": "Owner"
# }
# EOF

# ROLE_RESPONSE=$($FAB_CMD api connections/${CONNECTION_ID}/roleAssignments \
#   -A fabric -X post -i role.json)

# echo "==== ROLE RESPONSE ===="
# echo "$ROLE_RESPONSE"
# echo "======================="

# echo "🎉 HARD-CODE TEST COMPLETE"




# # ############################################
# # # Add SPN to Workspace (Hardcoded Test)
# # ############################################
# # echo $FABRIC_WORKSPACE_ID


# # echo "👤 Adding SPN to Workspace..."

# # WORKSPACE_ID="9f656d64-9fd4-4c38-8a27-be73e5f36836"
# # SPN_OBJECT_ID="a97fcf09-0a67-478d-bfd1-89550f20a33f"

# # cat > workspace_role.json <<EOF
# # {
# #   "principal": {
# #     "id": "${SPN_OBJECT_ID}",
# #     "type": "ServicePrincipal"
# #   },
# #   "role": "Admin"
# # }
# # EOF

# # cat > workspace_user.json <<EOF
# # {
# #   "identifier": "${SPN_OBJECT_ID}",
# #   "groupUserAccessRight": "Contributor",
# #   "principalType": "App"
# # }
# # EOF

# # RESPONSE=$($FAB_CMD api groups/${WORKSPACE_ID}/users \
# #   -A fabric -X post -i workspace_user.json)

# # echo "$RESPONSE"

# # if echo "$RESPONSE" | grep -q '"status_code": 200'; then
# #   echo "✅ SPN added to workspace"
# # else
# #   echo "❌ Failed to add SPN"
# #   exit 1
# # fi





# # ############################################
# # # 2️⃣ Check if connection already exists
# # ############################################

# # echo "🔎 Checking existing connection..."

# # CONNECTION_ID=$($FAB_CMD api connections -A fabric | \
# #   jq -r ".text.value[]? | select(.displayName==\"${DISPLAY_NAME}\") | .id"



# # if [ -n "$CONNECTION_ID" ]; then
# #   echo "✅ Connection already exists"
# #   echo "Connection ID: $CONNECTION_ID"
# # else
# #   echo "🚀 Creating new connection..."


# # cat > payload.json <<EOF
# # {
# #   "displayName": "${DISPLAY_NAME}",
# #   "connectivityType": "VirtualNetworkGateway",
# #   "gatewayId": "${GATEWAY_ID}",
# #   "privacyLevel": "Private",
# #   "connectionDetails": {
# #     "type": "Databricks",
# #     "creationMethod": "Databricks.Catalogs",
# #     "parameters": [
# #       {
# #         "dataType": "Text",
# #         "name": "host",
# #         "value": "${DATABRICKS_HOST}"
# #       },
# #       {
# #         "dataType": "Text",
# #         "name": "httpPath",
# #         "value": "${HTTP_PATH}"
# #       }
# #     ]
# #   },
# #   "credentialDetails": {
# #     "credentialType": "Basic",
# #     "singleSignOnType": "None",
# #     "connectionEncryption": "NotEncrypted",
# #     "skipTestConnection": false,
# #     "credentials": {
# #       "credentialType": "Basic",
# #       "username": "${SPN_CLIENT_ID_KV}",
# #       "password": "${SPN_SECRET_KV}"
# #     }
# #   }
# # }
# # EOF

# #   $FAB_CMD api connections -A fabric -X post -i payload.json

# #   echo "⏳ Fetching new connection ID..."

# #   CONNECTION_ID=$($FAB_CMD api connections -A fabric | \
# #   jq -r ".text.value[]? | select(.displayName==\"${DISPLAY_NAME}\") | .id"




# #   if [ -z "$CONNECTION_ID" ]; then
# #     echo "❌ Connection creation failed!"
# #     exit 1
# #   fi

# #   echo "✅ Connection created successfully"
# #   echo "Connection ID: $CONNECTION_ID"
# # fi

# # ############################################
# # # 3️⃣ Assign Group as Owner
# # ############################################

# # echo "👥 Assigning group as Owner..."

# # cat > role.json <<EOF
# # {
# #   "principal": {
# #     "id": "${GROUP_OBJECT_ID}",
# #     "type": "Group"
# #   },
# #   "role": "Owner"
# # }
# # EOF

# # $FAB_CMD api connections/${CONNECTION_ID}/roleAssignments \
# #   -A fabric -X post -i role.json

# # echo "✅ Group assigned successfully"

# # echo "============================================"
# # echo "🎉 FABRIC CONNECTION AUTOMATION COMPLETED"
# # echo "============================================"
