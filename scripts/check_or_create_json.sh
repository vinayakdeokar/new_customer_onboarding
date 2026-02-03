#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER_CODE=$2
ENV=$3

FILE="metadata/customers/${PRODUCT}-${CUSTOMER_CODE}.json"

echo "Checking customer metadata file: $FILE"

if [ -f "$FILE" ]; then
  echo "Customer JSON already exists"
else
  echo "Creating customer JSON"
  mkdir -p metadata/customers
  cat <<EOF > "$FILE"
{
  "customer_code": "${CUSTOMER_CODE}",
  "product": "${PRODUCT}",
  "environment": "${ENV}"
}
EOF
  echo "Customer JSON created"
fi

