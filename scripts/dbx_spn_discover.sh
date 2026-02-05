#!/bin/bash
set -euo pipefail

ENV_FILE="db_env.sh"
> "$ENV_FILE"   # overwrite safely

[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${TARGET_SPN_DISPLAY_NAME:?Missing TARGET_SPN_DISPLAY_NAME}"
: "${DATABRICKS_HOST:?Missing DATABRICKS_HOST}"
: "${DATABRICKS_TOKEN:?Missing DATABRICKS_TOKEN}"
: "${ACCOUNT_ID:?Missing ACCOUNT_ID}"

echo "🔎 Discovering SPN at Account level: $TARGET_SPN_DISPLAY_NAME"

SPN_RESPONSE=$(curl -sf -G \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/scim/v2/ServicePrincipals")

INTERNAL_ID=$(echo "$SPN_RESPONSE" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$SPN_RESPONSE" | jq -r '.Resources[0].applicationId // empty')

if [[ -z "$INTERNAL_ID" ]]; then
  echo "❌ SPN not found at account level"
  exit 1
fi

echo "✅ SPN Found"
echo "   Internal ID : $INTERNAL_ID"
echo "   App ID      : $APP_ID"

SECRET_LIST=$(curl -sf \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$INTERNAL_ID/credentials/secrets")

SECRET_COUNT=$(echo "$SECRET_LIST" | jq '.secrets | length // 0')

cat <<EOF >> "$ENV_FILE"
export DATABRICKS_INTERNAL_ID="$INTERNAL_ID"
export TARGET_APPLICATION_ID="$APP_ID"
export HAS_SECRETS="$SECRET_COUNT"
EOF

echo "🔐 Existing secrets count: $SECRET_COUNT"
