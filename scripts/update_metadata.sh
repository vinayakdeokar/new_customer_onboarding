#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER=$2
ENV=$3

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER}-users"
CATALOG_NAME="medicareadv"

BRONZE_SCHEMA="${PRODUCT}_${CUSTOMER}_bronze"
SILVER_SCHEMA="${PRODUCT}_${CUSTOMER}_silver"
GOLD_SCHEMA="${PRODUCT}_${CUSTOMER}_gold"

JSON_FILE="metadata/customers/customers.json"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Updating metadata JSON..."

jq --arg customer "$CUSTOMER" \
   --arg product "$PRODUCT" \
   --arg env "$ENV" \
   --arg spn "$SPN_NAME" \
   --arg group "$GROUP_NAME" \
   --arg catalog "$CATALOG_NAME" \
   --arg bronze "$BRONZE_SCHEMA" \
   --arg silver "$SILVER_SCHEMA" \
   --arg gold "$GOLD_SCHEMA" \
   --arg time "$TIMESTAMP" '
.customers[$customer] = {
  product: $product,
  environment: $env,
  spn_name: $spn,
  group_name: $group,
  catalog_name: $catalog,
  schemas: {
    bronze: $bronze,
    silver: $silver,
    gold: $gold
  },
  permissions: [
    "USE SCHEMA",
    "SELECT",
    "EXECUTE",
    "READ VOLUME"
  ],
  created_at: $time
}
' "$JSON_FILE" > tmp.json

mv tmp.json "$JSON_FILE"

git config user.email "jenkins@automation.com"
git config user.name "Jenkins Automation"

git add "$JSON_FILE"
git commit -m "Auto-added structured metadata for $CUSTOMER"
git push origin main

echo "Metadata updated successfully"
