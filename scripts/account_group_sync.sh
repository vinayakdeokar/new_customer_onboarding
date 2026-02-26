#!/bin/bash
set -e


: "${DATABRICKS_ACCOUNT_ID:?Missing ACCOUNT ID}"
: "${DATABRICKS_WORKSPACE_ID:?Missing WORKSPACE ID}"
: "${GROUP_NAME:?Missing GROUP NAME}"

ACCOUNTS_HOST="https://accounts.azuredatabricks.net"


echo " Fetching Azure tokens and Group Object ID..."
TOKEN=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken --output tsv)
AUTH="Authorization: Bearer ${TOKEN}"


AZURE_OBJ_ID=$(az ad group show --group "${GROUP_NAME}" --query id --output tsv)
echo "🎯 Azure Internal Object ID: ${AZURE_OBJ_ID}"


echo "🔎 Checking group at Account Level using Azure Object ID..."
LIST_RESP=$(curl -s -X GET "${ACCOUNTS_HOST}/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups?filter=externalId+eq+'${AZURE_OBJ_ID}'" \
  -H "${AUTH}")

GROUP_ID=$(echo "$LIST_RESP" | jq -r '.Resources[0].id // empty')


if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" == "null" ]; then
  echo "➕ Linking Azure group to Databricks Account Level..."
  CREATE_RESP=$(curl -s -X POST "${ACCOUNTS_HOST}/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups" \
    -H "${AUTH}" \
    -H "Content-Type: application/json" \
    -d "{
      \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
      \"displayName\": \"${GROUP_NAME}\",
      \"externalId\": \"${AZURE_OBJ_ID}\"
    }")
  GROUP_ID=$(echo "$CREATE_RESP" | jq -r '.id')
  echo "✅ Linked successfully! Databricks Internal ID: ${GROUP_ID}"
else
  echo "✅ Azure group already linked (Databricks Internal ID: ${GROUP_ID})"
fi
#!/bin/bash
set -e

: "${DATABRICKS_HOST:?Missing}"
: "${DATABRICKS_ADMIN_TOKEN:?Missing}"
: "${GROUP_NAME:?Missing}"

echo "🚀 Forcing group into WORKSPACE identity store..."

curl -s -X POST \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\"
  }" >/dev/null || true

echo "✅ Group materialized at Workspace level"

echo "Assigning group to workspace from ACCOUNT level..."

databricks account groups assign \
  --group-id 155340710301636 \
  --workspace-id 7405615166058644

echo "✅ Group assigned to workspace."


# SYNC_RESP=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
#   -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
#   -H "Content-Type: application/json" \
#   -d "{
#     \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
#     \"displayName\": \"${GROUP_NAME}\",
#     \"externalId\": \"${AZURE_OBJ_ID}\"
#   }")


echo "🔎 Checking if group is now in Workspace list..."
CHECK_WS=$(curl -s -X GET "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups?filter=displayName+eq+%22${GROUP_NAME}%22" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}")

IS_ADDED=$(echo "$CHECK_WS" | jq -r '.Resources[0].id // empty')

if [ -n "$IS_ADDED" ]; then
    echo "🎉 SUCCESS: Group '${GROUP_NAME}' is now DIRECTLY ADDED to Workspace!"
else
    echo "❌ ERROR: Group still not appearing in Workspace list. Please check Workspace Admin Permissions."
    exit 1
fi
