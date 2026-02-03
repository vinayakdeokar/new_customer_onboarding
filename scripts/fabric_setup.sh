#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER_CODE=$2
ENV=$3

WORKSPACE_NAME="${PRODUCT^^}-${CUSTOMER_CODE^^}-${ENV^^}"
SPN_NAME="sp-${PRODUCT}-${CUSTOMER_CODE}"

echo "Generating Power BI access token"

PBI_TOKEN=$(az account get-access-token \
  --resource https://analysis.windows.net/powerbi/api \
  --query accessToken -o tsv)

echo "Fetching Fabric workspace ID"

WS_ID=$(curl -s \
  -H "Authorization: Bearer $PBI_TOKEN" \
  https://api.powerbi.com/v1.0/myorg/groups \
  | jq -r ".value[] | select(.name==\"$WORKSPACE_NAME\") | .id")

if [ -z "$WS_ID" ]; then
  echo "ERROR: Workspace $WORKSPACE_NAME not found"
  exit 1
fi

echo "Adding SPN to Fabric workspace"

curl -s -X POST \
  -H "Authorization: Bearer $PBI_TOKEN" \
  -H "Content-Type: application/json" \
  https://api.powerbi.com/v1.0/myorg/groups/$WS_ID/users \
  -d "{
    \"identifier\": \"${SPN_NAME}\",
    \"groupUserAccessRight\": \"Viewer\",
    \"principalType\": \"App\"
  }" > /dev/null

echo "Fabric integration completed"

