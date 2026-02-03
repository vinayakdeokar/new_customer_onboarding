#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER_CODE=$2

SPN_NAME="sp-${PRODUCT}-${CUSTOMER_CODE}"
SECRET_NAME="${SPN_NAME}-secret"
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

echo "Fetching SPN secret from Key Vault"

SPN_SECRET=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "$SECRET_NAME" \
  --query value -o tsv)

echo "Configuring Databricks CLI"

databricks configure --host "$DATABRICKS_HOST" --token "$SPN_SECRET"

echo "Creating schemas"

for LAYER in bronze silver gold
do
  databricks sql execute --command "
  CREATE SCHEMA IF NOT EXISTS ${PRODUCT}_${CUSTOMER_CODE}_${LAYER};
  "
done

echo "Assigning permissions"

databricks sql execute --command "
GRANT USE_SCHEMA, SELECT
ON SCHEMA ${PRODUCT}_${CUSTOMER_CODE}_gold
TO \`${GROUP_NAME}\`;
"

databricks sql execute --command "
GRANT USE_SCHEMA, SELECT
ON SCHEMA ${PRODUCT}_${CUSTOMER_CODE}_gold
TO \`${SPN_NAME}\`;
"

echo "Databricks setup completed"
#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER_CODE=$2

SPN_NAME="sp-${PRODUCT}-${CUSTOMER_CODE}"
SECRET_NAME="${SPN_NAME}-secret"
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

echo "Fetching SPN secret from Key Vault"

SPN_SECRET=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "$SECRET_NAME" \
  --query value -o tsv)

echo "Configuring Databricks CLI"

databricks configure --host "$DATABRICKS_HOST" --token "$SPN_SECRET"

echo "Creating schemas"

for LAYER in bronze silver gold
do
  databricks sql execute --command "
  CREATE SCHEMA IF NOT EXISTS ${PRODUCT}_${CUSTOMER_CODE}_${LAYER};
  "
done

echo "Assigning permissions"

databricks sql execute --command "
GRANT USE_SCHEMA, SELECT
ON SCHEMA ${PRODUCT}_${CUSTOMER_CODE}_gold
TO \`${GROUP_NAME}\`;
"

databricks sql execute --command "
GRANT USE_SCHEMA, SELECT
ON SCHEMA ${PRODUCT}_${CUSTOMER_CODE}_gold
TO \`${SPN_NAME}\`;
"

echo "Databricks setup completed"

