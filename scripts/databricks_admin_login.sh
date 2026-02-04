#!/bin/bash
set -e

echo "Logging into Databricks using ADMIN SPN"

export DATABRICKS_HOST="$DATABRICKS_HOST"
export DATABRICKS_CLIENT_ID="$DATABRICKS_ADMIN_CLIENT_ID"
export DATABRICKS_CLIENT_SECRET="$DATABRICKS_ADMIN_CLIENT_SECRET"
export DATABRICKS_AUTH_TYPE=oauth

databricks auth env >/dev/null

echo "Databricks admin login successful"
