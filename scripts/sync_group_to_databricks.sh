#!/bin/bash
set -e

: "${DATABRICKS_HOST:?Missing DATABRICKS_HOST}"
: "${DATABRICKS_ADMIN_TOKEN:?Missing DATABRICKS_ADMIN_TOKEN}"
: "${GROUP_NAME:?Missing GROUP_NAME}"

echo "➡️ Ensuring Group '$GROUP_NAME' is synced to workspace..."

GROUP_EXISTS=$(curl -s \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups?filter=displayName+eq+%22$GROUP_NAME%22" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}")

if [[ $(echo "$GROUP_EXISTS" | jq -r '.totalResults') == "0" ]]; then
  echo "🔗 Group not found. Syncing..."
  curl -s -X POST \
    "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
    -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"displayName\": \"$GROUP_NAME\"}" > /dev/null
  echo "✅ Group synced."
else
  echo "✅ Group already synced."
fi

echo "➡️ Adding SQL Warehouse entitlement..."

GROUP_ID=$(curl -s \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups?filter=displayName+eq+%22$GROUP_NAME%22" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  | jq -r '.Resources[0].id')

curl -s -X PATCH \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups/$GROUP_ID" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
    "Operations": [{
      "op": "add",
      "path": "entitlements",
      "value": [{"value": "databricks-sql-access"}]
    }]
  }'

echo "🎉 Group sync + entitlement done"
