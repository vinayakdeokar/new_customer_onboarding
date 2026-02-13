#!/bin/bash
set -e

FAB_CMD="$WORKSPACE/fabricenv/bin/fab"

echo "============================================"
echo "🚀 FABRIC VNET CONNECTION AUTOMATION STARTED"
echo "Customer: $CUSTOMER_CODE"
echo "============================================"

echo "Using FAB from:"
ls -l $FAB_CMD

############################################
# VARIABLES
############################################

DISPLAY_NAME="db-vnet-${CUSTOMER_CODE}"
GATEWAY_ID="34377033-6f6f-433a-9a66-3095e996f65c"
HTTP_PATH="/sql/1.0/warehouses/${DATABRICKS_SQL_WAREHOUSE_ID}"

############################################
# 1️⃣ Fabric Login
############################################

echo "🔐 Configuring Fabric CLI for CI..."

$FAB_CMD config set encryption_fallback_enabled true

echo "🔐 Logging into Fabric..."

$FAB_CMD auth login \
  -u $FABRIC_CLIENT_ID \
  -p $FABRIC_CLIENT_SECRET \
  --tenant $FABRIC_TENANT_ID \
  --resource https://analysis.windows.net/powerbi/api

echo "✅ Fabric login successful"



############################################
# 2️⃣ Check if connection already exists
############################################

echo "🔎 Checking existing connection..."

echo "=== RAW CONNECTION RESPONSE ==="
$FAB_CMD api connections -A fabric
echo "================================"

exit 1



if [ -n "$CONNECTION_ID" ]; then
  echo "✅ Connection already exists"
  echo "Connection ID: $CONNECTION_ID"
else
  echo "🚀 Creating new connection..."

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
      "username": "${SPN_CLIENT_ID_KV}",
      "password": "${SPN_SECRET_KV}"
    }
  }
}
EOF

  $FAB_CMD api connections -A fabric -X post -i payload.json

  echo "⏳ Fetching new connection ID..."

  CONNECTION_ID=$($FAB_CMD api connections -A fabric | jq -r ".value[] | select(.displayName==\"${DISPLAY_NAME}\") | .id")


  if [ -z "$CONNECTION_ID" ]; then
    echo "❌ Connection creation failed!"
    exit 1
  fi

  echo "✅ Connection created successfully"
  echo "Connection ID: $CONNECTION_ID"
fi

############################################
# 3️⃣ Assign Group as Owner
############################################

echo "👥 Assigning group as Owner..."

cat > role.json <<EOF
{
  "principal": {
    "id": "${GROUP_OBJECT_ID}",
    "type": "Group"
  },
  "role": "Owner"
}
EOF

$FAB_CMD api connections/${CONNECTION_ID}/roleAssignments \
  -A fabric -X post -i role.json

echo "✅ Group assigned successfully"

echo "============================================"
echo "🎉 FABRIC CONNECTION AUTOMATION COMPLETED"
echo "============================================"
