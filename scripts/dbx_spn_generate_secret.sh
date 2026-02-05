#!/bin/bash
set -euo pipefail
source db_env.sh

: "${DATABRICKS_INTERNAL_ID:?Missing INTERNAL ID}"
: "${HAS_SECRETS:?Missing secret count}"
: "${DATABRICKS_HOST:?Missing host}"
: "${DATABRICKS_TOKEN:?Missing token}"
: "${ACCOUNT_ID:?Missing account id}"
: "${TARGET_SPN_DISPLAY_NAME:?Missing SPN name}"

if [[ "$HAS_SECRETS" -gt 0 ]]; then
  echo "ℹ️ OAuth secret already exists. Skipping creation."
  exit 0
fi

echo "🔐 Generating OAuth secret (Account-level API)"

PAYLOAD=$(jq -n \
  --arg comment "oauth-secret-for-$TARGET_SPN_DISPLAY_NAME" \
  '{ lifetime_seconds: 31536000, comment: $comment }')

RESPONSE=$(curl -sf -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets")

OAUTH_SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // empty')

if [[ -z "$OAUTH_SECRET_VALUE" ]]; then
  echo "❌ Secret generation failed"
  echo "Response: $RESPONSE"
  exit 1
fi

echo "export FINAL_OAUTH_SECRET=\"$OAUTH_SECRET_VALUE\"" >> db_env.sh
echo "✅ OAuth secret generated (one-time)"
