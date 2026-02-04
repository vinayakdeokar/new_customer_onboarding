#!/bin/bash
set -e

source spn.env

echo "Assigning Customer SPN to Databricks workspace"
echo "SPN_APP_ID=$SPN_APP_ID"

databricks workspace-assignments create \
  --principal-id "$SPN_APP_ID" \
  --permissions USER

echo "Customer SPN assigned to workspace successfully"
