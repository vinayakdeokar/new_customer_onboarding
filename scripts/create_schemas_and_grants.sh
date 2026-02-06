[Pipeline] }
[Pipeline] // withCredentials
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Create Schemas & Grants)
[Pipeline] withCredentials
Masking supported pattern matches of $DATABRICKS_HOST or $DATABRICKS_ADMIN_TOKEN or $DATABRICKS_SQL_WAREHOUSE_ID or $CATALOG_NAME
[Pipeline] {
[Pipeline] sh
+ export PRODUCT=m360
+ export CUSTOMER_CODE=vinayak-002
+ chmod +x scripts/create_schemas_and_grants.sh
+ ./scripts/create_schemas_and_grants.sh
------------------------------------------------
Catalog   : ****
Schemas   : m360-vinayak-002_bronze | m360-vinayak-002_silver | m360-vinayak-002_gold
------------------------------------------------
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
