pipeline {
  agent any

  parameters {
    string(name: 'CUSTOMER_CODE', description: 'Customer code like cx11')
    string(name: 'PRODUCT', defaultValue: 'm360', description: 'Product name')
    string(name: 'ENV', defaultValue: 'dev', description: 'Environment')
    string(
      name: 'SPN_NAME',
      description: 'Azure Entra ID SPN name (e.g. sp-m360-vinayak-003)'
    )
  }

  environment {
    KV_NAME = 'kv-databricks-fab'
  }

  stages {
    // all stages here
  }
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

    stage('Databricks SPN OAuth Secret (Account Level)') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'DATABRICKS_ACCOUNT_ID'),
          string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID')
        ]) {
          sh '''
            # ✅ TAKE FROM JENKINS PARAM
            export TARGET_SPN_DISPLAY_NAME="${SPN_NAME}"
    
            echo "Using SPN: $TARGET_SPN_DISPLAY_NAME"
    
            chmod +x scripts/dbx_spn_discover.sh
            chmod +x scripts/dbx_spn_generate_secret.sh
    
            scripts/dbx_spn_discover.sh
            scripts/dbx_spn_generate_secret.sh
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
    
    //         chmod +x scripts/dbx_spn_discover.sh
    //         chmod +x scripts/dbx_spn_generate_secret.sh
    
    //         scripts/dbx_spn_discover.sh
    //         scripts/dbx_spn_generate_secret.sh
    //       '''
    //     }
    //   }
    // }

    // =========================================================
    // FINAL ACCESS MANAGEMENT STAGE (SHARED / DEDICATED)
    // =========================================================
    stage('Databricks Access Manager') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_HOST', variable: 'DATABRICKS_HOST'),
          string(credentialsId: 'DATABRICKS_ADMIN_TOKEN', variable: 'DATABRICKS_ADMIN_TOKEN'),
          string(credentialsId: 'DATABRICKS_SQL_WAREHOUSE_ID', variable: 'DATABRICKS_SQL_WAREHOUSE_ID'),
          string(credentialsId: 'DATABRICKS_CATALOG_NAME', variable: 'CATALOG_NAME'),
          string(credentialsId: 'STORAGE_BRONZE_ROOT', variable: 'STORAGE_BRONZE_ROOT')
        ]) {
    
          sh '''
            chmod +x scripts/databricks_access_manager.sh
    
            # =================================================
            # MODE SELECTION
            # =================================================
            export MODE=DEDICATED
            # export MODE=SHARED
    
            export PRODUCT=${PRODUCT}
            export CUSTOMER_CODE=${CUSTOMER_CODE}
            export CATALOG_NAME=${CATALOG_NAME}
    
            # 🔴 THIS WAS MISSING
            export STORAGE_BRONZE_ROOT=${STORAGE_BRONZE_ROOT}
    
            # (optional debug – masked but format visible)
            echo "DEBUG STORAGE_BRONZE_ROOT=${STORAGE_BRONZE_ROOT}"
    
            ./scripts/databricks_access_manager.sh
          '''
        }
      }
    }


  }
}
