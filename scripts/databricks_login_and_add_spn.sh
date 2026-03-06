#!/bin/bash
set -euo pipefail

PRODUCT=$1
CUSTOMER=$2

if [ -z "$PRODUCT" ] || [ -z "$CUSTOMER" ]; then
  echo " PRODUCT or CUSTOMER missing"
  exit 1
fi

SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

echo "CLIENT_ID length:"
echo ${#AZURE_CLIENT_ID}

echo "HOST:"
echo $DATABRICKS_HOST | cut -c1-30


echo " Target Azure SPN name: $SPN_NAME"

# --------------------------------------------------
# Step 1️ Azure login check
# --------------------------------------------------
az account show > /dev/null

# --------------------------------------------------
# Step 2️ Find Azure SPN
# --------------------------------------------------
SPN_CLIENT_ID=$(az ad sp list \
  --display-name "$SPN_NAME" \
  --query "[0].appId" \
  -o tsv)

if [ -z "$SPN_CLIENT_ID" ]; then
  echo " Azure SPN not found: $SPN_NAME"
  exit 1
fi



echo " Azure SPN found"
#echo "   ➜ Client ID: $SPN_CLIENT_ID"

# --------------------------------------------------
# Step 3️ Databricks login check
# --------------------------------------------------
#databricks clusters list > /dev/null
#echo " Databricks CLI login successful"

# --------------------------------------------------
# Step 3️⃣ Generate Databricks AAD Token
# --------------------------------------------------

: "${AZURE_CLIENT_ID:?missing}"
: "${AZURE_CLIENT_SECRET:?missing}"
: "${AZURE_TENANT_ID:?missing}"
: "${DATABRICKS_HOST:?missing}"

echo " Logging into Azure with SPN..."

az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" > /dev/null

echo " Generating Databricks AAD token..."

DATABRICKS_ADMIN_TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

if [ -z "$DATABRICKS_ADMIN_TOKEN" ]; then
  echo " Failed to generate Databricks token"
  exit 1
fi

echo $DATABRICKS_HOST

# --------------------------------------------------
# Step 4️ Check if SPN already exists in Databricks
# --------------------------------------------------
echo " Checking if SPN already exists in Databricks workspace..."

EXISTING_SPN=$(curl -s \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  | jq -r '.Resources[].applicationId' \
  | grep -w "$SPN_CLIENT_ID" || true)

if [ -n "$EXISTING_SPN" ]; then
  echo " SPN already exists in Databricks – skipping creation"
  exit 0
fi

# --------------------------------------------------
# Step 5️ snyc SPN in Databricks
# --------------------------------------------------




echo " Adding Azure SPN to Databricks workspace..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"applicationId\": \"$SPN_CLIENT_ID\",
        \"displayName\": \"$SPN_NAME\"
      }")


if [ "$HTTP_CODE" = "201" ]; then
  echo " SPN successfully added to Databricks"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "ℹ SPN already exists (409 Conflict) – safe to continue"
else
  echo " Failed to add SPN (HTTP $HTTP_CODE)"
  exit 1
fi

# #!/bin/bash
# set -euo pipefail

# PRODUCT=$1
# CUSTOMER=$2

# if [ -z "$PRODUCT" ] || [ -z "$CUSTOMER" ]; then
#   echo "❌ PRODUCT or CUSTOMER missing"
#   exit 1
# fi

# SPN_NAME="sp-${PRODUCT}-${CUSTOMER}"

# echo "🔎 Target Azure SPN name: $SPN_NAME"

# # --------------------------------------------------
# # Step 1️⃣ Azure login check
# # --------------------------------------------------
# az account show > /dev/null

# # --------------------------------------------------
# # Step 2️⃣ Find Azure SPN
# # --------------------------------------------------
# SPN_CLIENT_ID=$(az ad sp list \
#   --display-name "$SPN_NAME" \
#   --query "[0].appId" \
#   -o tsv)

# if [ -z "$SPN_CLIENT_ID" ]; then
#   echo "❌ Azure SPN not found: $SPN_NAME"
#   exit 1
# fi

# echo "✅ Azure SPN found"
# #echo "   ➜ Client ID: $SPN_CLIENT_ID"

# # --------------------------------------------------
# # Step 3️⃣ Databricks login check
# # --------------------------------------------------
# databricks clusters list > /dev/null
# echo "✅ Databricks CLI login successful"

# # --------------------------------------------------
# # Step 4️⃣ Check if SPN already exists in Databricks
# # --------------------------------------------------
# echo "🔍 Checking if SPN already exists in Databricks workspace..."

# EXISTING_SPN=$(curl -s \
#   -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
#   "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
#   | jq -r '.Resources[].applicationId' \
#   | grep -w "$SPN_CLIENT_ID" || true)

# if [ -n "$EXISTING_SPN" ]; then
#   echo "✅ SPN already exists in Databricks – skipping creation"
#   exit 0
# fi

# # --------------------------------------------------
# # Step 5️⃣ snyc SPN in Databricks
# # --------------------------------------------------




# echo "➕ Adding Azure SPN to Databricks workspace..."

# HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
#   -X POST \
#   "$DATABRICKS_HOST/api/2.0/preview/scim/v2/ServicePrincipals" \
#   -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
#   -H "Content-Type: application/json" \
#   -d "{
#         \"applicationId\": \"$SPN_CLIENT_ID\",
#         \"displayName\": \"$SPN_NAME\"
#       }")




# if [ "$HTTP_CODE" = "201" ]; then
#   echo "🎉 SPN successfully added to Databricks"
# elif [ "$HTTP_CODE" = "409" ]; then
#   echo "ℹ️ SPN already exists (409 Conflict) – safe to continue"
# else
#   echo "❌ Failed to add SPN (HTTP $HTTP_CODE)"
#   exit 1
# fi
