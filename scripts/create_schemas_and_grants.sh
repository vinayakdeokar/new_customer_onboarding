 export CUSTOMER_CODE=vinayak-002
+ chmod +x scripts/create_schemas_and_grants.sh
+ ./scripts/create_schemas_and_grants.sh
------------------------------------------------
Catalog   : ****
Schemas   : m360-vinayak-002_bronze | m360-vinayak-002_silver | m360-vinayak-002_gold
Group     : grp-m360-vinayak-002-users
------------------------------------------------
➡️ Executing: CREATE SCHEMA IF NOT EXISTS ****.m360-vinayak-002_bronze
❌ Failed SQL: CREATE SCHEMA IF NOT EXISTS ****.m360-vinayak-002_bronze
{"statement_id":"01f10352-bc12-178c-89ed-46e3bfe85160","status":{"state":"FAILED","error":{"error_code":"BAD_REQUEST","message":"\n[INVALID_IDENTIFIER] The unquoted identifier m360-vinayak-002_bronze is invalid and must be back quoted as: `m360-vinayak-002_bronze`.\nUnquoted identifiers can only contain ASCII letters ('a' - 'z', 'A' - 'Z'), digits ('0' - '9'), and underbar ('_').\nUnquoted identifiers must also not start with a digit.\nDifferent data sources and meta stores may impose additional restrictions on valid identifiers. SQLSTATE: 42602 (line 1, pos 44)\n\n== SQL ==\nCREATE SCHEMA IF NOT EXISTS ****.m360-vinayak-002_bronze\n--------------------------------------------^^^\n"},"sql_state":"42602"}}
[Pipeline] }
[Pipeline] // withCredentials
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
ERROR: script returned exit code 1
Finished: FAILURE
