#!/bin/bash
set -e

: "${CUSTOMER_CODE:?Missing CUSTOMER_CODE}"
: "${STORAGE_ACCOUNT:?Missing STORAGE_ACCOUNT}"
: "${CONTAINER_NAME:?Missing CONTAINER_NAME}"

echo "---------------------------------------"
echo "Creating ADLS folder if not exists"
echo "Customer : $CUSTOMER_CODE"
echo "---------------------------------------"

EXISTS=$(az storage fs directory exists \
  --account-name "$STORAGE_ACCOUNT" \
  --file-system "$CONTAINER_NAME" \
  --name "$CUSTOMER_CODE" \
  --auth-mode login \
  --query "exists" -o tsv)

if [ "$EXISTS" = "true" ]; then
  echo "✅ Folder already exists"
else
  az storage fs directory create \
    --account-name "$STORAGE_ACCOUNT" \
    --file-system "$CONTAINER_NAME" \
    --name "$CUSTOMER_CODE" \
    --auth-mode login

  echo "✅ Folder created successfully"
fi
