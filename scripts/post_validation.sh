#!/bin/bash
set -e

echo "========================================="
echo "🚀 STARTING POST VALIDATION CHECKS"
echo "========================================="

################################################
# 1️⃣ SPN Login Test (Databricks)
################################################

echo "🔐 Testing Databricks SPN Login..."

databricks clusters list >/dev/null 2>&1

echo "✅ Databricks login successful"


################################################
# 2️⃣ Storage Access Test
################################################

echo "📦 Testing ADLS Storage Access..."

az login --service-principal \
  -u $AZURE_CLIENT_ID \
  -p $AZURE_CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID >/dev/null

az storage blob list \
  --account-name stmedicareadvmcr \
  --container-name bronze \
  --auth-mode login >/dev/null

echo "✅ Storage access successful"


################################################
# 3️⃣ Fabric Connection Test
################################################

echo "🔗 Testing Fabric Connection..."

. fabricenv/bin/activate

fab api connections -A fabric >/dev/null

echo "✅ Fabric API reachable"


################################################
# 4️⃣ SQL Connectivity Test
################################################

echo "🗄 Testing SQL Connectivity..."

sqlcmd -S your-server.database.windows.net \
       -d your-database \
       -U $DB_USER \
       -P $DB_PASS \
       -Q "SELECT 1" >/dev/null

echo "✅ SQL connection successful"

echo "========================================="
echo "🎉 ALL VALIDATION CHECKS PASSED"
echo "========================================="
