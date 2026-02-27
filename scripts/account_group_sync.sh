#!/bin/bash
set -e

# आवश्यक व्हेरिएबल्स
: "${DATABRICKS_ACCOUNT_ID:?Missing ACCOUNT ID}"
: "${DATABRICKS_WORKSPACE_ID:?Missing WORKSPACE ID}"
: "${GROUP_NAME:?Missing GROUP NAME}"

ACCOUNTS_HOST="https://accounts.azuredatabricks.net"

# १. Azure कडून Access Token आणि ग्रुपचा Internal Object ID मिळवणे
echo "🔐 Fetching Azure tokens and Group Object ID..."
TOKEN=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken --output tsv)
AUTH="Authorization: Bearer ${TOKEN}"

# Azure मधून ग्रुपचा Internal ID (Object ID) काढणे
AZURE_OBJ_ID=$(az ad group show --group "${GROUP_NAME}" --query id --output tsv)
echo "🎯 Azure Internal Object ID: ${AZURE_OBJ_ID}"

# २. Account Level वर ग्रुप आधीच लिंक आहे का तपासणे (externalId द्वारे)
echo "🔎 Checking group at Account Level using Azure Object ID..."
LIST_RESP=$(curl -s -X GET "${ACCOUNTS_HOST}/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups?filter=externalId+eq+'${AZURE_OBJ_ID}'" \
  -H "${AUTH}")

GROUP_ID=$(echo "$LIST_RESP" | jq -r '.Resources[0].id // empty')

# ३. जर ग्रुप लिंक नसेल, तर तो Account Level वर 'Link' करणे
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


# ४. ग्रुपला Workspace मध्ये असाइन करणे (लिंक करणे)
echo "🔗 Assigning group '${GROUP_NAME}' to Workspace..."

# Account-level Groups API वापरून वर्कस्पेसला ग्रुप असाइन करणे
# टीप: आपण 'PUT' वापरत आहोत जेणेकरून तो ग्रुप वर्कस्पेसच्या लिस्टमध्ये 'Directly Assigned' दिसेल.
ASSIGN_RESP=$(curl -s -X PUT "${ACCOUNTS_HOST}/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/workspaces/${DATABRICKS_WORKSPACE_ID}/permissions/groups/${GROUP_ID}" \
  -H "${AUTH}" \
  -H "Content-Type: application/json" \
  -d "{
    \"permissions\": [\"MEMBER\"]
  }")

if echo "$ASSIGN_RESP" | grep -q "error"; then
    echo "❌ Assignment Failed: $ASSIGN_RESP"
    exit 1
else
    echo "✅ Successfully assigned and added to workspace list!"
fi

# echo "⏳ Waiting 30 seconds for UI refresh..."
# sleep 30

# ४. ग्रुपला वर्कस्पेसच्या 'Directly Assigned' लिस्टमध्ये ॲड करणे
echo "🚀 Formally adding Group '${GROUP_NAME}' to Workspace list..."

# वर्कस्पेस लेव्हलवर ग्रुप 'Create' करण्याचा प्रयत्न करणे. 
# जरी तो अकाउंट लेव्हलवर असला, तरी हा SCIM कॉल त्याला वर्कस्पेसच्या मुख्य यादीत खेचून आणतो.
SYNC_RESP=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
  -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
    \"displayName\": \"${GROUP_NAME}\",
    \"externalId\": \"${AZURE_OBJ_ID}\"
  }")

# ५. व्हेरिफिकेशन: ग्रुप आता लिस्टमध्ये आला आहे का हे चेक करणे
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
# #!/bin/bash
# set -e

# # आवश्यक व्हेरिएबल्स
# : "${DATABRICKS_ACCOUNT_ID:?Missing ACCOUNT ID}"
# : "${DATABRICKS_WORKSPACE_ID:?Missing WORKSPACE ID}"
# : "${GROUP_NAME:?Missing GROUP NAME}"

# ACCOUNTS_HOST="https://accounts.azuredatabricks.net"

# # १. Azure कडून Access Token आणि ग्रुपचा Internal Object ID मिळवणे
# echo "🔐 Fetching Azure tokens and Group Object ID..."
# TOKEN=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken --output tsv)
# AUTH="Authorization: Bearer ${TOKEN}"

# # Azure मधून ग्रुपचा Internal ID (Object ID) काढणे
# AZURE_OBJ_ID=$(az ad group show --group "${GROUP_NAME}" --query id --output tsv)
# echo "🎯 Azure Internal Object ID: ${AZURE_OBJ_ID}"

# # २. Account Level वर ग्रुप आधीच लिंक आहे का तपासणे (externalId द्वारे)
# echo "🔎 Checking group at Account Level using Azure Object ID..."
# LIST_RESP=$(curl -s -X GET "${ACCOUNTS_HOST}/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups?filter=externalId+eq+'${AZURE_OBJ_ID}'" \
#   -H "${AUTH}")

# GROUP_ID=$(echo "$LIST_RESP" | jq -r '.Resources[0].id // empty')

# # ३. जर ग्रुप लिंक नसेल, तर तो Account Level वर 'Link' करणे
# if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" == "null" ]; then
#   echo "➕ Linking Azure group to Databricks Account Level..."
#   CREATE_RESP=$(curl -s -X POST "${ACCOUNTS_HOST}/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2/Groups" \
#     -H "${AUTH}" \
#     -H "Content-Type: application/json" \
#     -d "{
#       \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
#       \"displayName\": \"${GROUP_NAME}\",
#       \"externalId\": \"${AZURE_OBJ_ID}\"
#     }")
#   GROUP_ID=$(echo "$CREATE_RESP" | jq -r '.id')
#   echo "✅ Linked successfully! Databricks Internal ID: ${GROUP_ID}"
# else
#   echo "✅ Azure group already linked (Databricks Internal ID: ${GROUP_ID})"
# fi

# # # ४. ग्रुपला Workspace मध्ये असाइन करणे (लिंक करणे)
# # echo "🔗 Assigning group '${GROUP_NAME}' to Workspace..."

# # # Account-level Groups API वापरून वर्कस्पेसला ग्रुप असाइन करणे
# # # टीप: आपण 'PUT' वापरत आहोत जेणेकरून तो ग्रुप वर्कस्पेसच्या लिस्टमध्ये 'Directly Assigned' दिसेल.
# # ASSIGN_RESP=$(curl -s -X PUT "${ACCOUNTS_HOST}/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/workspaces/${DATABRICKS_WORKSPACE_ID}/permissions/groups/${GROUP_ID}" \
# #   -H "${AUTH}" \
# #   -H "Content-Type: application/json" \
# #   -d "{
# #     \"permissions\": [\"MEMBER\"]
# #   }")

# # if echo "$ASSIGN_RESP" | grep -q "error"; then
# #     echo "❌ Assignment Failed: $ASSIGN_RESP"
# #     exit 1
# # else
# #     echo "✅ Successfully assigned and added to workspace list!"
# # fi

# # echo "⏳ Waiting 30 seconds for UI refresh..."
# # sleep 30

# # ४. ग्रुपला वर्कस्पेसच्या 'Directly Assigned' लिस्टमध्ये ॲड करणे
# echo "🚀 Formally adding Group '${GROUP_NAME}' to Workspace list..."

# # वर्कस्पेस लेव्हलवर ग्रुप 'Create' करण्याचा प्रयत्न करणे. 
# # जरी तो अकाउंट लेव्हलवर असला, तरी हा SCIM कॉल त्याला वर्कस्पेसच्या मुख्य यादीत खेचून आणतो.
# SYNC_RESP=$(curl -s -X POST "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups" \
#   -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}" \
#   -H "Content-Type: application/json" \
#   -d "{
#     \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:Group\"],
#     \"displayName\": \"${GROUP_NAME}\",
#     \"externalId\": \"${AZURE_OBJ_ID}\"
#   }")

# # ५. व्हेरिफिकेशन: ग्रुप आता लिस्टमध्ये आला आहे का हे चेक करणे
# echo "🔎 Checking if group is now in Workspace list..."
# CHECK_WS=$(curl -s -X GET "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups?filter=displayName+eq+%22${GROUP_NAME}%22" \
#   -H "Authorization: Bearer ${DATABRICKS_ADMIN_TOKEN}")

# IS_ADDED=$(echo "$CHECK_WS" | jq -r '.Resources[0].id // empty')

# if [ -n "$IS_ADDED" ]; then
#     echo "🎉 SUCCESS: Group '${GROUP_NAME}' is now DIRECTLY ADDED to Workspace!"
# else
#     echo "❌ ERROR: Group still not appearing in Workspace list. Please check Workspace Admin Permissions."
#     exit 1
# fi
