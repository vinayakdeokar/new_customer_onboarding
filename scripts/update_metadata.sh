#!/bin/bash

PRODUCT=$1
CUSTOMER_CODE=$2
ENVIRONMENT=$3

FILE="metadata/customers/customers.json"

GROUP="grp-${PRODUCT}-${CUSTOMER_CODE}-users"
SPN="sp-${PRODUCT}-${CUSTOMER_CODE}"

# Check if already exists
EXISTS=$(jq -r --arg cc "$CUSTOMER_CODE" \
  '.customers[] | select(.customer_code==$cc)' "$FILE")

if [ -n "$EXISTS" ]; then
  echo "⚠️ Customer already exists in JSON"
  exit 0
fi

# Build new JSON object
NEW_ENTRY=$(jq -n \
  --arg cc "$CUSTOMER_CODE" \
  --arg prod "$PRODUCT" \
  --arg env "$ENVIRONMENT" \
  --arg grp "$GROUP" \
  --arg spn "$SPN" \
  '{
    customer_code: $cc,
    product: $prod,
    environment: $env,
    group: $grp,
    group_permissions: [
      "USE_CATALOG",
      "USE_SCHEMA",
      "SELECT",
      "EXECUTE",
      "READ_VOLUME"
    ],
    spn: $spn,
    spn_permissions: [
      "CAN_USE"
    ]
  }')

# Append safely (NO overwrite of whole file)
jq --argjson newCustomer "$NEW_ENTRY" \
  '.customers += [$newCustomer]' \
  "$FILE" > tmp.json && mv tmp.json "$FILE"

echo "✅ Customer appended successfully"
