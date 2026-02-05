# #!/bin/bash
# set -e

# PRODUCT=$1
# CUSTOMER=$2

# FILE="metadata/customers/${PRODUCT}-${CUSTOMER}.json"

# echo "Checking customer metadata: $FILE"

# if [ -f "$FILE" ]; then
#   echo "Customer already exists in metadata."
#   echo "CUSTOMER_EXISTS=true" > customer_status.env
# else
#   echo "Customer NOT found in metadata."
#   echo "CUSTOMER_EXISTS=false" > customer_status.env
# fi

#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER=$2

FILE="metadata/customers/customers.json"

echo "Checking customer in JSON: product=$PRODUCT customer=$CUSTOMER"

if [ ! -f "$FILE" ]; then
  echo "ERROR: customers.json not found"
  exit 1
fi

FOUND=$(jq -r \
  --arg product "$PRODUCT" \
  --arg customer "$CUSTOMER" \
  '.customers[] | select(.product==$product and .customer_code==$customer) | .customer_code' \
  "$FILE")

if [ -n "$FOUND" ]; then
  echo "Customer found in metadata JSON"
  echo "CUSTOMER_EXISTS=true" > customer_status.env
else
  echo "Customer NOT found in metadata JSON"
  echo "CUSTOMER_EXISTS=false" > customer_status.env
fi
