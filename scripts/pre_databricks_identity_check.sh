#!/bin/bash
set -e

PRODUCT=$1
CUSTOMER=$2

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"
GROUP_NAME="grp-${PRODUCT}-${CUSTOMER}-users"

KV_NAME="kv-databricks-fab"
KV_SECRET_NAME="sp-${PRODUCT}-${CUSTOMER}-oauth-secret"

echo "----- PRE-DATABRICKS IDENTITY CHECK -----"

# -------------------------------
# Validate inputs
# -------------------------------
if [ -z "$CATALOG_NAME" ]; then
  echo "❌ CATALOG_NAME not provided from Jenkins"
  exit 1
fi

# -------------------------------
# Azure checks
# -------------------------------
echo "Checking Azure Entra ID SPN: ${SPN_NAME}"
az ad sp list --display-name "${SPN_NAME}" --query "[].appId" -o tsv | grep -q .

echo "Checking Azure Entra ID Group: ${GROUP_NAME}"
az ad group show --group "${GROUP_NAME}" >/dev/null

# -------------------------------
# ALWAYS persist context (KEY FIX)
# -------------------------------
echo "--------------------------------------------------"
echo "Saving Databricks context for next stages"

echo "export CATALOG_NAME=${CATALOG_NAME}" > db_env.sh
echo "export CUSTOMER_CODE=${CUSTOMER}" >> db_env.sh
echo "export DATA_GROUP=${GROUP_NAME}" >> db_env.sh
echo "export BRONZE_STORAGE_ROOT=abfss://bronze@<storage-account>.dfs.core.windows.net/${CUSTOMER}" >> db_env.sh

echo "Context saved:"
cat db_env.sh
echo "--------------------------------------------------"

# -------------------------------
# Secret check (NON-BLOCKING)
# -------------------------------
echo "Checking Databricks OAuth secret in Key Vault: ${KV_SECRET_NAME}"
if az keyvault secret show \
    --vault-name "${KV_NAME}" \
    --name "${KV_SECRET_NAME}" \
    --query value -o tsv >/dev/null 2>&1; then
  echo "✅ Databricks OAuth secret already present."
else
  echo "⚠️ Databricks OAuth secret NOT found (will be created later)."
fi

echo "✅ Pre Databricks identity check completed"
exit 0
