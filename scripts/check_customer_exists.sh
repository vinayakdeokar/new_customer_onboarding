#!/bin/bash
set -e

PRODUCT="$1"
CUSTOMER="$2"

# Always resolve repo root correctly (Jenkins + local safe)
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

JSON_FILE="$BASE_DIR/metadata/customers/customers.json"
STATUS_FILE="$BASE_DIR/customer_status.env"

echo "Checking customer in JSON"
echo "Product  : $PRODUCT"
echo "Customer : $CUSTOMER"
echo "JSON     : $JSON_FILE"

# Validate JSON file
if [ ! -f "$JSON_FILE" ]; then
  echo "ERROR: customer.json not found at $JSON_FILE"
  exit 1
fi

# Find customer
RESULT=$(jq -r --arg p "$PRODUCT" --arg c "$CUSTOMER" '
  .customers[]
  | select(.product == $p and .customer_code == $c)
' "$JSON_FILE")

# Customer NOT found
if [ -z "$RESULT" ]; then
  echo "Customer NOT found in metadata JSON"
  echo "CUSTOMER_EXISTS=false" > "$STATUS_FILE"
  exit 0
fi

# Extract details
CUSTOMER_CODE=$(echo "$RESULT" | jq -r '.customer_code')
PRODUCT_NAME=$(echo "$RESULT" | jq -r '.product')
ENVIRONMENT=$(echo "$RESULT" | jq -r '.environment')
GROUP_NAME=$(echo "$RESULT" | jq -r '.group')
SPN_NAME=$(echo "$RESULT" | jq -r '.spn')
GROUP_PERMISSIONS=$(echo "$RESULT" | jq -r '.group_permissions | join(",")')
SPN_PERMISSIONS=$(echo "$RESULT" | jq -r '.spn_permissions | join(",")')

# Print details (visible in Jenkins logs)
echo "CUSTOMER_EXISTS=true"
echo "CUSTOMER_CODE=$CUSTOMER_CODE"
echo "PRODUCT=$PRODUCT_NAME"
echo "ENVIRONMENT=$ENVIRONMENT"
echo "GROUP_NAME=$GROUP_NAME"
echo "GROUP_PERMISSIONS=$GROUP_PERMISSIONS"
echo "SPN_NAME=$SPN_NAME"
echo "SPN_PERMISSIONS=$SPN_PERMISSIONS"

# Write env file for Jenkins
cat <<EOF > "$STATUS_FILE"
CUSTOMER_EXISTS=true
CUSTOMER_CODE=$CUSTOMER_CODE
PRODUCT=$PRODUCT_NAME
ENVIRONMENT=$ENVIRONMENT
GROUP_NAME=$GROUP_NAME
GROUP_PERMISSIONS=$GROUP_PERMISSIONS
SPN_NAME=$SPN_NAME
SPN_PERMISSIONS=$SPN_PERMISSIONS
EOF

echo "Customer details written to $STATUS_FILE"
