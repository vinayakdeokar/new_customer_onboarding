pipeline {
  agent any

  parameters {
    string(name: 'CUSTOMER_CODE', defaultValue: '')
    string(name: 'PRODUCT', defaultValue: 'm360')
    string(name: 'ENV', defaultValue: 'dev')
  }

  environment {
    KV_NAME = 'kv-dataplatform'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Customer Metadata') {
      steps {
        sh """
        chmod +x scripts/check_or_create_json.sh
        scripts/check_or_create_json.sh ${PRODUCT} ${CUSTOMER_CODE} ${ENV}
        """
      }
    }

    stage('Azure Login') {
      steps {
        sh """
        chmod +x scripts/azure_login.sh
        scripts/azure_login.sh
        """
      }
    }

    stage('SPN Secret to KeyVault') {
      steps {
        sh """
        chmod +x scripts/spn_secret_to_kv.sh
        scripts/spn_secret_to_kv.sh ${PRODUCT} ${CUSTOMER_CODE}
        """
      }
    }

    stage('Databricks Setup') {
      steps {
        sh """
        chmod +x scripts/databricks_setup.sh
        scripts/databricks_setup.sh ${PRODUCT} ${CUSTOMER_CODE}
        """
      }
    }

    stage('Fabric Setup') {
      steps {
        sh """
        chmod +x scripts/fabric_setup.sh
        scripts/fabric_setup.sh ${PRODUCT} ${CUSTOMER_CODE} ${ENV}
        """
      }
    }
  }
}

