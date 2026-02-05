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

    // stage('Databricks Login') {
    //   steps {
    //     withCredentials([
    //       string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
    //       string(credentialsId: 'DATABRICKS_CLIENT_ID', variable: 'DATABRICKS_CLIENT_ID'),
    //       string(credentialsId: 'DATABRICKS_CLIENT_SECRET', variable: 'DATABRICKS_CLIENT_SECRET'),
    //       string(credentialsId: 'DATABRICKS_TENANT_ID', variable: 'DATABRICKS_TENANT_ID')
    //     ]) {
    //       sh '''
    //         chmod +x scripts/databricks_login.sh
    //         scripts/databricks_login.sh
    //       '''
    //     }
    //   }
    // }

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

    stage('Databricks SPN OAuth Secret (Account Level)') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
          string(credentialsId: 'DATABRICKS_TOKEN', variable: 'DATABRICKS_TOKEN'),
          string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'ACCOUNT_ID')
        ]) {
          sh '''
            export TARGET_SPN_DISPLAY_NAME="sp-m360-vinayak-002"
            chmod +x scripts/dbx_spn_discover.sh scripts/dbx_spn_generate_secret.sh
            scripts/dbx_spn_discover.sh
            scripts/dbx_spn_generate_secret.sh
          '''
        }
      }
    }





  
    
    // stage('Generate & Store Databricks SPN OAuth Secret') {
    //   steps {
    //     withCredentials([
    //       string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
    //       string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ADMIN_TOKEN'),
    //       string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'DATABRICKS_ACCOUNT_ID'), // 👈 ही नवीन लाइन ॲड केली आहे
    //       string(credentialsId: 'kv-name', variable: 'KV_NAME')
    //     ]) {
    //       sh '''
    //         chmod +x scripts/generate_and_store_databricks_spn_secret.sh
    //         ./scripts/generate_and_store_databricks_spn_secret.sh "sp-m360-vinayak-002"
    //       '''
    //     }
    //   }
    }
  }
}
