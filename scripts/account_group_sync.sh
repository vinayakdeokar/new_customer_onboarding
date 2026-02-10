# #!/bin/bash
# set -e

# : "${DATABRICKS_ACCOUNT_ID:?Missing}"
# : "${WORKSPACE_ID:?Missing}"
# : "${GROUP_NAME:?Missing}"

# HOST="https://accounts.azuredatabricks.net"

# echo "🔐 Getting Databricks Account token..."
# TOKEN=$(az account get-access-token \
#   --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
#   --query accessToken -o tsv)

# AUTH="Authorization: Bearer $TOKEN"

# echo "🔎 Checking group at ACCOUNT level..."
# GROUP_ID=$(curl -s -H "$AUTH" \
#   "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups?filter=displayName eq \"$GROUP_NAME\"" \
#   | jq -r '.Resources[0].id // empty')

# if [ -z "$GROUP_ID" ]; then
#   echo "➕ Creating account-level group..."
#   GROUP_ID=$(curl -s -X POST -H "$AUTH" \
#     "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/scim/v2/Groups" \
#     -H "Content-Type: application/json" \
#     -d "{\"displayName\":\"$GROUP_NAME\"}" \
#     | jq -r '.id')
# fi

# echo "✅ Account group ID: $GROUP_ID"

# echo "🔗 Attaching group to workspace..."
# curl -s -X POST -H "$AUTH" \
#   "$HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID/workspaces/$WORKSPACE_ID/permissions/groups/$GROUP_ID" \
#   >/dev/null

#!/bin/bash
set -e

# --- पायरी १: Azure ग्रुपला Databricks Account मध्ये 'Link' करणे ---
# आपण नावावरून ग्रुप शोधण्यापेक्षा थेट 'POST' करतोय. 
# जर ग्रुप आधीच असेल, तर हा कॉल एरर देणार नाही, फक्त माहिती अपडेट करेल.
echo "🚀 Linking Azure Group '${GROUP_NAME}' using Object ID..."

CREATE_RESPONSE=$(curl -s -X POST "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\",
    \"externalId\": \"${AZURE_OBJ_ID}\"
  }")

# ग्रुपचा अंतर्गत ID (Internal Principal ID) काढणे
GROUP_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id // empty')

# जर वरील स्टेपमध्ये ID मिळाला नाही (ग्रुप आधीच असेल तर), तर GET करून शोधणे
if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" == "null" ]; then
    echo "ℹ️ Group already exists, fetching Internal ID..."
    GROUP_ID=$(curl -s -X GET "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups?filter=displayName+eq+%22${GROUP_NAME}%22" \
      -H "Authorization: Bearer ${DATABRICKS_TOKEN}" | jq -r '.Resources[0].id // empty')
fi

if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" == "null" ]; then
    echo "❌ ERROR: Group ID सापडला नाही. Azure Object ID तपासा."
    exit 1
fi

echo "✅ Internal ID Found: $GROUP_ID"

# --- पायरी २: ग्रुपला Workspace मध्ये असाइन करणे ---
# जोपर्यंत ही स्टेप होत नाही, तोपर्यंत युनिटी कॅटलॉग (Schema) मध्ये हा ग्रुप दिसत नाही.
echo "🔗 Assigning group to Workspace: ${WORKSPACE_ID}..."

curl -s -X PUT "https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/workspaces/${WORKSPACE_ID}/permissionassignments/principals/${GROUP_ID}" \
  -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ "permissions": ["USER"] }'

echo "🎉 SUCCESS: Group आता Workspace मध्ये आहे!"
