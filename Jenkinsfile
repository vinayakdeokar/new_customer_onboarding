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

    stage('Databricks Login') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
          string(credentialsId: 'DATABRICKS_CLIENT_ID', variable: 'DATABRICKS_CLIENT_ID'),
          string(credentialsId: 'DATABRICKS_CLIENT_SECRET', variable: 'DATABRICKS_CLIENT_SECRET'),
          string(credentialsId: 'DATABRICKS_TENANT_ID', variable: 'DATABRICKS_TENANT_ID')
        ]) {
          sh '''
            chmod +x scripts/databricks_login.sh
            scripts/databricks_login.sh
          '''
        }
      }
    }
    
    stage('Add SPN to Databricks Workspace') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
          string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ADMIN_TOKEN')
        ]) {
          sh '''
            chmod +x scripts/add_spn_to_databricks.sh
            scripts/add_spn_to_databricks.sh \
              ${PRODUCT} \
              ${CUSTOMER_CODE}
          '''
        }
      }
    }
    
    stage('Create Databricks OAuth Secret') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
          string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ADMIN_TOKEN')
        ]) {
          sh '''
            chmod +x scripts/create_databricks_oauth_secret.sh
            scripts/create_databricks_oauth_secret.sh sp-m360-vinayak-002 90
          '''
        }
      }
    }

  }
}
