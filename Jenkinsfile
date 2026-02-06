pipeline {
  agent any

  parameters {
    string(name: 'CUSTOMER_CODE', description: 'Customer code like cx11')
    string(name: 'PRODUCT', defaultValue: 'm360', description: 'Product name')
    string(name: 'ENV', defaultValue: 'dev', description: 'Environment')
  }

  environment {
    KV_NAME = 'kv-databricks-fab'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        echo "Customer=${params.CUSTOMER_CODE}, Product=${params.PRODUCT}, Env=${params.ENV}"
      }
    }

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

    stage('Databricks SPN Setup') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
          string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ADMIN_TOKEN')
        ]) {
          sh '''
            chmod +x scripts/databricks_login_and_add_spn.sh
            scripts/databricks_login_and_add_spn.sh "${PRODUCT}" "${CUSTOMER_CODE}"
          '''
        }
      }
    }

    // stage('Databricks SPN OAuth Secret (Account Level)') {
    //   steps {
    //     withCredentials([
    //       string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'DATABRICKS_ACCOUNT_ID'),
    //       string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID')
    //     ]) {
    //       sh '''
    //         export TARGET_SPN_DISPLAY_NAME="sp-m360-vinayak-002"
    //
    //         chmod +x scripts/dbx_spn_discover.sh
    //         chmod +x scripts/dbx_spn_generate_secret.sh
    //
    //         scripts/dbx_spn_discover.sh
    //         scripts/dbx_spn_generate_secret.sh
    //       '''
    //     }
    //   }
    // }

    stage('Create Schemas & Grants') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_SQL_WAREHOUSE_ID', variable: 'DATABRICKS_SQL_WAREHOUSE_ID')
        ]) {
          sh '''
            chmod +x scripts/create_schemas_and_grants.sh
            scripts/create_schemas_and_grants.sh
          '''
        }
      }
    }
    

  }
}
