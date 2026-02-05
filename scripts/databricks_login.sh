#!/bin/bash
set -e

echo "Setting Databricks authentication context"

export DATABRICKS_HOST="$DATABRICKS_HOST"
export DATABRICKS_CLIENT_ID="$DATABRICKS_CLIENT_ID"
export DATABRICKS_CLIENT_SECRET="$DATABRICKS_CLIENT_SECRET"
export DATABRICKS_TENANT_ID="$DATABRICKS_TENANT_ID"

# Test call
databricks clusters list > /dev/null

echo "Databricks login successful"
