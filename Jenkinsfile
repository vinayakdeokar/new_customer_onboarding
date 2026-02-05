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

    stage('Add External SPN by Application ID') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ACCOUNT_TOKEN'),
          string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'DATABRICKS_ACCOUNT_ID'),
          string(credentialsId: 'AZURE_SPN_APP_ID', variable: 'AZURE_SPN_APP_ID')
        ]) {
          withEnv([
            "DATABRICKS_ACCOUNT_HOST=https://accounts.azuredatabricks.net",
            "DATABRICKS_WORKSPACE_ID=7405618110977329"
          ]) {
            sh '''
              echo "Workspace ID = $DATABRICKS_WORKSPACE_ID"
              chmod +x scripts/add_external_spn_by_appid_and_assign.sh
              scripts/add_external_spn_by_appid_and_assign.sh
            '''
          }
        }
      }
    }



  
    
    stage('Create Databricks Account SPN & OAuth Secret') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_TOKEN'),
          string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'ACCOUNT_ID')
        ]) {
          withEnv([
            "PRODUCT=${params.PRODUCT}",
            "CUSTOMER=${params.CUSTOMER_CODE}",
            "DATABRICKS_HOST=https://accounts.azuredatabricks.net"
          ]) {
            sh '''
              chmod +x scripts/create_account_spn_and_oauth_secret.sh
              scripts/create_account_spn_and_oauth_secret.sh
            '''
          }
        }
      }
    }


  }
}
