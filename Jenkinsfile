pipeline {
    agent any

    tools {
        git 'git'
    }

    parameters {

        string(
            name: 'CUSTOMER_CODE',
            description: 'Customer code like vinayak-003'
        )

        string(
            name: 'PRODUCT',
            defaultValue: 'm360',
            description: 'Product name'
        )

        string(
            name: 'ENV',
            defaultValue: 'dev',
            description: 'Environment'
        )

        string(
            name: 'WORKSPACE_ID',
            defaultValue: '7405618110977329',
            description: 'Databricks Workspace ID'
        )

        string(
            name: 'SPN_NAME',
            description: 'Azure Entra ID SPN name (e.g. sp-m360-vinayak-003)'
        )

        string(
            name: 'ACCESS_GROUP',
            description: 'Azure Entra ID group name (single)'
        )
    }

    environment {
        KV_NAME = 'kv-databricks-fab'
    }

    stages {

        stage('Init Workspace') {
            steps {
                sh '''
                    echo "🧹 Cleaning old env state"
                    rm -f db_env.sh
                '''
            }
        }

        // --------------------------------------------------
        // CHECKOUT
        // --------------------------------------------------
        stage('Checkout') {
            steps {
                checkout scm
                echo "Customer=${params.CUSTOMER_CODE}, Product=${params.PRODUCT}, Env=${params.ENV}"
                echo "SPN=${params.SPN_NAME}"
            }
        }

        // --------------------------------------------------
        // CUSTOMER CHECK
        // --------------------------------------------------
        stage('Customer Check') {
            steps {
                sh '''
                    set +x
                    chmod +x scripts/check_customer_exists.sh
                    scripts/check_customer_exists.sh \
                        ${PRODUCT} \
                        ${CUSTOMER_CODE} > /dev/null 2>&1
                '''
                script {
                    def status = readFile('customer_status.env')
                    if (status.contains("CUSTOMER_EXISTS=true")) {
                        currentBuild.result = 'SUCCESS'
                        error("STOP_PIPELINE")
                    }
                }
            }
        }

        // --------------------------------------------------
        // AZURE LOGIN
        // --------------------------------------------------
        stage('Azure Login') {
            steps {
                withCredentials([
                    string(credentialsId: 'AZURE_CLIENT_ID', variable: 'AZURE_CLIENT_ID'),
                    string(credentialsId: 'AZURE_CLIENT_SECRET', variable: 'AZURE_CLIENT_SECRET'),
                    string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID'),
                    string(credentialsId: 'AZURE_SUBSCRIPTION_ID', variable: 'AZURE_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        set +x
                        chmod +x scripts/azure_login.sh
                        scripts/azure_login.sh
                    '''
                }
            }
        }

        // --------------------------------------------------
        // PRE-DATABRICKS CHECK
        // --------------------------------------------------
        stage('Pre Databricks Identity Check') {
            steps {
                withCredentials([
                    string(credentialsId: 'DATABRICKS_CATALOG_NAME', variable: 'CATALOG_NAME')
                ]) {
                    sh '''
                        set +x
                        chmod +x scripts/pre_databricks_identity_check.sh
                        scripts/pre_databricks_identity_check.sh "${PRODUCT}" "${CUSTOMER_CODE}"
                    '''
                }
            }
        }

//         // --------------------------------------------------
//         // SPN SETUP (WORKSPACE)
//         // --------------------------------------------------
//         stage('Databricks SPN Setup') {
//             steps {
//                 withCredentials([
//                     string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
//                     string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ADMIN_TOKEN')
//                 ]) {
//                     sh '''
//                         chmod +x scripts/databricks_login_and_add_spn.sh
//                         scripts/databricks_login_and_add_spn.sh "${PRODUCT}" "${CUSTOMER_CODE}"
//                     '''
//                 }
//             }
//         }

//         // --------------------------------------------------
//         // SPN OAUTH SECRET (ACCOUNT LEVEL)
//         // --------------------------------------------------
//         stage('Databricks SPN OAuth Secret (Account Level)') {
//             steps {
//                 withCredentials([
//                     string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'DATABRICKS_ACCOUNT_ID'),
//                     string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID')
//                 ]) {
//                     sh """
//                         export TARGET_SPN_DISPLAY_NAME="${params.SPN_NAME}"

//                         echo "Using SPN: \$TARGET_SPN_DISPLAY_NAME"

//                         chmod +x scripts/dbx_spn_discover.sh
//                         chmod +x scripts/dbx_spn_generate_secret.sh

//                         scripts/dbx_spn_discover.sh
//                         scripts/dbx_spn_generate_secret.sh
//                     """
//                 }
//             }
//         }

//         // --------------------------------------------------
//         // ACCOUNT GROUP SYNC
//         // --------------------------------------------------
//         stage('Databricks Account Group Sync') {
//             steps {
//                 withCredentials([
//                     string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
//                     string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'DATABRICKS_ACCOUNT_ID'),
//                     string(credentialsId: 'DATABRICKS_WORKSPACE_ID', variable: 'DATABRICKS_WORKSPACE_ID'),
//                     string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ADMIN_TOKEN')
//                 ]) {
//                     sh '''
//                         export GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"

//                         chmod +x scripts/account_group_sync.sh
//                         ./scripts/account_group_sync.sh
//                     '''
//                 }
//             }
//         }
//         stage('Create ADLS Bronze Folder') {
//             steps {
//                 sh '''
//                 chmod +x scripts/create_bronze_folder.sh
//                 export STORAGE_ACCOUNT=stmedicareadvmcr
//                 export CONTAINER_NAME=bronze
//                 scripts/create_bronze_folder.sh
//                 '''
//             }
//         }


//         // --------------------------------------------------
//         // SCHEMAS & GRANTS
//         // --------------------------------------------------
//         stage('Schemas & Grants') {
//             steps {
//                 withCredentials([
//                     string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
//                     string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ADMIN_TOKEN'),
//                     string(credentialsId: 'DATABRICKS_SQL_WAREHOUSE_ID', variable: 'DATABRICKS_SQL_WAREHOUSE_ID'),
//                     string(credentialsId: 'DATABRICKS_CATALOG_NAME', variable: 'CATALOG_NAME'),
//                     string(credentialsId: 'STORAGE_BRONZE_ROOT', variable: 'STORAGE_BRONZE_ROOT')
//                 ]) {
//                     sh '''
//                         chmod +x scripts/databricks_schema_and_grants.sh
//                         ./scripts/databricks_schema_and_grants.sh
//                     '''
//                 }
//             }
//         }

//         // stage('Create Fabric Connection') {
//         //     steps {
//         //         withCredentials([
//         //             string(credentialsId: 'AZURE_CLIENT_ID', variable: 'DB_USER'),
//         //             string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DB_PASS'),
//         //             string(credentialsId: 'DATABRICKS_HOST', variable: 'DB_HOST')
//         //         ]) {
                
//         //             sh '''
//         //             export DISPLAY_NAME="db-vnet-automation-spn-5"
//         //             export GATEWAY_ID="34377033-6f6f-433a-9a66-3095e996f65c"
//         //             export DB_HTTP_PATH="/sql/1.0/warehouses/559747c78f71249c"
//         //             chmod +x scripts/fabric_connection.sh
                
//         //             ./scripts/fabric_connection.sh
//         //             '''
//         //         }

//         //     }
//         // }

//         stage('Update Customer Metadata') {
//             when {
//                 expression { currentBuild.currentResult == 'SUCCESS' }
//             }
//             steps {
//                 withCredentials([usernamePassword(
//                     credentialsId: 'github-pat',
//                     usernameVariable: 'GIT_USERNAME',
//                     passwordVariable: 'GIT_TOKEN'
//                 )]) {
        
//                     sh '''
//                     set -e
        
//                     echo "✔ Updating customer metadata..."
        
//                     chmod +x scripts/update_metadata.sh
//                     ./scripts/update_metadata.sh $PRODUCT $CUSTOMER_CODE $ENV > /dev/null 2>&1
        
//                     git config user.name "jenkins-bot"
//                     git config user.email "jenkins@automation.local"
        
//                     git add metadata/customers/customers.json
        
//                     if git diff --cached --quiet; then
//                         echo "✔ No metadata changes"
//                         exit 0
//                     fi
        
//                     git commit -m "Auto-added customer $CUSTOMER_CODE" > /dev/null 2>&1
        
//                     git push https://$GIT_USERNAME:$GIT_TOKEN@github.com/vinayakdeokar/new_customer_onboarding.git HEAD:main > /dev/null 2>&1
        
//                     echo "✔ Metadata pushed to Git"
//                     '''
//                 }
//             }
//         }


        



    }
}
