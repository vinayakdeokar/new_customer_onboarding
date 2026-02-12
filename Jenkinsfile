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
        stage('Fabric Databricks Connection') {
            steps {
                withCredentials([
                    string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID'),
                    string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
                    string(credentialsId: 'DATABRICKS_SQL_PATH', variable: 'DATABRICKS_SQL_PATH')
                ]) {
                    sh '''
                        echo "===================================="
                        echo "🚀 STARTING FABRIC CONNECTION STAGE"
                        echo "===================================="
        
                        export PRODUCT="${PRODUCT}"
                        export CUSTOMER_CODE="${CUSTOMER_CODE}"
                        export KV_NAME="${KV_NAME}"
                        export AZURE_TENANT_ID="${AZURE_TENANT_ID}"
                        export DATABRICKS_HOST="${DATABRICKS_HOST}"
                        export DATABRICKS_SQL_PATH="${DATABRICKS_SQL_PATH}"
        
                        chmod +x scripts/fabric_create_connection.sh
                        ./scripts/fabric_create_connection.sh
                    '''
                }
            }
        }


                


    }
}
