#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER=$2

FILE="metadata/customers/${PRODUCT}-${CUSTOMER}.json"

echo "Checking customer metadata: $FILE"

if [ -f "$FILE" ]; then
  echo "Customer already exists in metadata."
  echo "CUSTOMER_EXISTS=true" > customer_status.env
else
  echo "Customer NOT found in metadata."
  echo "CUSTOMER_EXISTS=false" > customer_status.env
fi
