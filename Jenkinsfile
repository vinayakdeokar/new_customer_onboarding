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
            echo "Customer already onboarded. Stopping pipeline."
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
            echo "Jenkins SPN AppId=$AZURE_CLIENT_ID"
            chmod +x scripts/azure_login.sh
            scripts/azure_login.sh
          '''
        }
      }
    }

    stage('Pre Databricks Identity Check') {
      steps {
        sh '''
          chmod +x scripts/pre_databricks_identity_check.sh
          scripts/pre_databricks_identity_check.sh \
            ${PRODUCT} \
            ${CUSTOMER_CODE}
        '''
      }
    }

    stage('Add SPN to Databricks Workspace') {
      steps {
        sh '''
          chmod +x scripts/add_spn_to_databricks.sh
          scripts/add_spn_to_databricks.sh \
            ${PRODUCT} \
            ${CUSTOMER_CODE}
        '''
      }
    }

  }
}
