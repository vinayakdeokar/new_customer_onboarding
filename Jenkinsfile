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

    stage('Customer Metadata') {
      steps {
        sh """
        chmod +x scripts/check_or_create_json.sh
        scripts/check_or_create_json.sh \
          ${params.PRODUCT} \
          ${params.CUSTOMER_CODE} \
          ${params.ENV}
        """
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

    stage('Databricks Setup') {
      steps {
        sh """
        chmod +x scripts/databricks_setup.sh
        scripts/databricks_setup.sh \
          ${params.PRODUCT} \
          ${params.CUSTOMER_CODE}
        """
      }
    }

    stage('Fabric Setup') {
      steps {
        sh """
        chmod +x scripts/fabric_setup.sh
        scripts/fabric_setup.sh \
          ${params.PRODUCT} \
          ${params.CUSTOMER_CODE} \
          ${params.ENV}
        """
      }
    }
  }
}

