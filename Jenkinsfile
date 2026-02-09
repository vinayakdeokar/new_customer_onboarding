pipeline {
  agent any

  parameters {
    string(name: 'CUSTOMER_CODE', description: 'Customer code like vinayak-003')
    string(name: 'PRODUCT', defaultValue: 'm360', description: 'Product name')
    string(name: 'ENV', defaultValue: 'dev', description: 'Environment')
    string(name: 'SPN_NAME',
      description: 'Azure Entra ID SPN name (e.g. sp-m360-vinayak-003)'
    )
    string(
    name: 'ACCESS_GROUP',
    description: 'Azure Entra ID group name (single)'
  )
}
  }

  environment {
    KV_NAME = 'kv-databricks-fab'
  }

  stages {

    // --------------------------------------------------
    // INIT – CLEAN OLD STATE
    // --------------------------------------------------
    stage('Init Workspace') {
      steps {
        sh '''
          echo "🧹 Cleaning old env state"
          rm -f db_env.sh
        '''
      }
    }

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

    // --------------------------------------------------
    // SPN SETUP (WORKSPACE)
    // --------------------------------------------------
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

    // --------------------------------------------------
    // SPN OAUTH SECRET (ACCOUNT LEVEL)
    // --------------------------------------------------
    stage('Databricks SPN OAuth Secret (Account Level)') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'DATABRICKS_ACCOUNT_ID'),
          string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID')
        ]) {
          sh """
            export TARGET_SPN_DISPLAY_NAME="${params.SPN_NAME}"
          
            echo "Using SPN: \$TARGET_SPN_DISPLAY_NAME"
          
            chmod +x scripts/dbx_spn_discover.sh
            chmod +x scripts/dbx_spn_generate_secret.sh
          
            scripts/dbx_spn_discover.sh
            scripts/dbx_spn_generate_secret.sh
          """

        }
      }
    }

    stage('Databricks Group Workspace Sync') {
      steps {
        withCredentials([
          string(credentialsId: 'DATABRICKS_ACCOUNT_ID', variable: 'DATABRICKS_ACCOUNT_ID'),
          string(credentialsId: 'DATABRICKS_CLIENT_ID', variable: 'DATABRICKS_CLIENT_ID'),
          string(credentialsId: 'DATABRICKS_CLIENT_SECRET', variable: 'DATABRICKS_CLIENT_SECRET'),
          string(credentialsId: 'DATABRICKS_TENANT_ID', variable: 'DATABRICKS_TENANT_ID')
        ]) {
          sh """
            export GROUP_NAME="grp-${PRODUCT}-${CUSTOMER_CODE}-users"
            export WORKSPACE_NAME="<<EXACT_DATABRICKS_WORKSPACE_NAME>>"
    
            chmod +x scripts/sync_group_to_databricks.sh
            scripts/sync_group_to_databricks.sh
          """
        }
      }
    }


    // --------------------------------------------------
    // UNITY CATALOG ACCESS
    // --------------------------------------------------
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

            export MODE=DEDICATED
            export PRODUCT=${PRODUCT}
            export CUSTOMER_CODE=${CUSTOMER_CODE}
            export CATALOG_NAME=${CATALOG_NAME}
            export STORAGE_BRONZE_ROOT=${STORAGE_BRONZE_ROOT}

            echo "DEBUG STORAGE_BRONZE_ROOT=${STORAGE_BRONZE_ROOT}"

            ./scripts/databricks_access_manager.sh
          '''
        }
      }
    }

  }
}
