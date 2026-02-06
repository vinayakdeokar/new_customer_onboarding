#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER=$2

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER}-users"

KV_NAME="kv-databricks-fab"
KV_SECRET_NAME="sp-${PRODUCT}-${CUSTOMER}-oauth-secret"

echo "----- PRE-DATABRICKS IDENTITY CHECK -----"

echo "Checking Azure Entra ID SPN: ${SPN_NAME}"
if ! az ad sp list --display-name "${SPN_NAME}" --query "[].appId" -o tsv | grep -q .; then
  echo "ERROR: SPN ${SPN_NAME} not found in Azure Entra ID"
  exit 1
fi
echo "SPN exists."

echo "Checking Azure Entra ID Group: ${GROUP_NAME}"
if ! az ad group show --group "${GROUP_NAME}" >/dev/null 2>&1; then
  echo "ERROR: Group ${GROUP_NAME} not found in Azure Entra ID"
  exit 1
fi
echo "Group exists."

echo "Checking Databricks OAuth secret in Key Vault: ${KV_SECRET_NAME}"
if az keyvault secret show \
    --vault-name "${KV_NAME}" \
    --name "${KV_SECRET_NAME}" \
    --query value -o tsv >/dev/null 2>&1; then
  echo "Databricks OAuth secret already present in Key Vault."
  echo "Proceeding to Databricks setup."
  exit 0
fi

echo "--------------------------------------------------"
echo "Databricks OAuth secret NOT found."
echo ""
echo "MANUAL ACTION REQUIRED (ONE TIME):"
echo ""
exit 1

# --------------------------------------------------
# Persist Databricks context for next stages
# --------------------------------------------------

if [ -z "$CATALOG_NAME" ]; then
  echo "❌ CATALOG_NAME not provided from Jenkins"
  exit 1
fi

echo "export CATALOG_NAME=${CATALOG_NAME}" > db_env.sh
echo "export CUSTOMER_CODE=${CUSTOMER}" >> db_env.sh
echo "export DATA_GROUP=${GROUP_NAME}" >> db_env.sh

# Bronze external storage (example – adjust storage name if needed)
echo "export BRONZE_STORAGE_ROOT=abfss://bronze@<storage-account>.dfs.core.windows.net/${CUSTOMER}" >> db_env.sh

echo "--------------------------------------------------"
echo "Databricks context saved:"
echo "  CATALOG_NAME = $CATALOG_NAME"
echo "  CUSTOMER     = $CUSTOMER"
echo "  DATA_GROUP   = $GROUP_NAME"
echo "--------------------------------------------------"
