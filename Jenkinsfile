// chef-infra pipeline: test the cookbooks, then promote the policy dev -> uat -> prod.
// Triggered by any push to this repo (Jenkins polls GitHub every ~2 minutes).
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 60, unit: 'MINUTES')
  }

  triggers { pollSCM('H/2 * * * *') }

  environment {
    CHEF_USER       = 'jenkins'
    CHEF_SERVER_URL = 'https://chef-server.lab.internal/organizations/lab'
  }

  stages {
    stage('Lint (Cookstyle)') {
      steps { sh 'cookstyle --display-cop-names cookbooks/' }
    }

    stage('Unit tests (ChefSpec)') {
      steps {
        sh "rm -rf cookbooks/*@tmp && cd cookbooks/base && cinc exec rspec"
        sh "rm -rf cookbooks/*@tmp && cd cookbooks/myapp && cinc exec rspec"
      }
    }

    stage('Integration (Test Kitchen + InSpec)') {
      steps {
        dir('cookbooks/myapp') { sh 'kitchen test --destroy=always' }
      }
    }

    stage('Resolve policy') {
      steps { sh 'cinc install policyfiles/myapp.rb' }
    }

    stage('Deploy dev') {
      steps { script { deployPolicy('dev') } }
    }

    stage('Promote to uat') {
      steps { script { deployPolicy('uat') } }
    }

    stage('Approve prod') {
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          input message: 'dev and uat are green. Promote this policy to PROD?', ok: 'Promote'
        }
      }
    }

    stage('Promote to prod') {
      steps { script { deployPolicy('prod') } }
    }
  }

  post {
    always {
      junit allowEmptyResults: true, testResults: 'reports/*.xml'
      archiveArtifacts allowEmptyArchive: true, artifacts: 'policyfiles/*.lock.json'
    }
  }
}

// Same lock file, pushed to each group in turn = true promotion.
def deployPolicy(String group) {
  withCredentials([
    file(credentialsId: 'chef-jenkins-key', variable: 'CHEF_CLIENT_KEY'),
    sshUserPrivateKey(credentialsId: 'deploy-ssh-key', keyFileVariable: 'DEPLOY_KEY', usernameVariable: 'DEPLOY_USER')
  ]) {
    sh "ci/deploy_policy.sh ${group}"
  }
}
