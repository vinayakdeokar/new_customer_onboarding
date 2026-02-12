pipeline {
    agent any

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
                    chmod +x scripts/check_customer_exists.sh
                    scripts/check_customer_exists.sh \
                        ${PRODUCT} \
                        ${CUSTOMER_CODE}
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
                        chmod +x scripts/pre_databricks_identity_check.sh
                        scripts/pre_databricks_identity_check.sh "${PRODUCT}" "${CUSTOMER_CODE}"
                    '''
                }
            }
        }

        stage('Install Node Dependencies') {
            steps {
                sh '''
                    npm install
                    npx playwright install chromium
                '''
            }
        }


        // --------------------------------------------------
        // FABRIC DATABRICKS CONNECTION
        // --------------------------------------------------
       // --------------------------------------------------
        stage('Fabric UI Connection') {
            steps {
                withCredentials([
                    string(credentialsId: 'FABRIC_USER', variable: 'FABRIC_USER'),
                    string(credentialsId: 'FABRIC_PASS', variable: 'FABRIC_PASS'),
                    string(credentialsId: 'FABRIC_WORKSPACE_ID', variable: 'FABRIC_WORKSPACE_ID')
                ]) {
                    sh '''
                        echo "===================================="
                        echo "🚀 STARTING FABRIC UI AUTOMATION"
                        echo "Customer: ${CUSTOMER_CODE}"
                        echo "===================================="
        
                        # Export required variables
                        export CUSTOMER_CODE="${CUSTOMER_CODE}"
                        export DATABRICKS_HOST="${DATABRICKS_HOST}"
                        export DATABRICKS_SQL_PATH="${DATABRICKS_SQL_PATH}"
                        export FABRIC_WORKSPACE_ID="${FABRIC_WORKSPACE_ID}"
        
                        echo "🔐 Fetching SPN credentials from KeyVault..."
        
                        export SPN_CLIENT_ID=$(az keyvault secret show \
                          --vault-name ${KV_NAME} \
                          --name sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-client-id \
                          --query value -o tsv)
        
                        export SPN_SECRET=$(az keyvault secret show \
                          --vault-name ${KV_NAME} \
                          --name sp-${PRODUCT}-${CUSTOMER_CODE}-oauth-secret \
                          --query value -o tsv)
        
                        if [ -z "$SPN_CLIENT_ID" ] || [ -z "$SPN_SECRET" ]; then
                            echo "❌ Failed to fetch SPN credentials"
                            exit 1
                        fi
        
                        echo "🚀 Launching Playwright automation..."
        
                        node scripts/fabric_ui_create_connection.js
                    '''
                }
            }
        }


                


    }
}
