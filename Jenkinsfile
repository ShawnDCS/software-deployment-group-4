// SWE40006 Group 4 — Number Guessing Game pipeline.
// Level 1 version: Checkout -> Test -> Build. Push / Deploy stages are added in Level 3.
pipeline {
  agent any

  options {
    skipDefaultCheckout()          // we check out explicitly in the 'Checkout' stage
    timestamps()
    disableConcurrentBuilds()      // one deployment at a time
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 20, unit: 'MINUTES')
  }

  environment {
    IMAGE = "${env.DOCKERHUB_USER}/guessgame"   // DOCKERHUB_USER is a global env var set by JCasC
  }

  stages {
    stage('Checkout') {
      steps {
        script {
          // With skipDefaultCheckout, GIT_COMMIT is not set automatically: take it from checkout's result.
          def scmVars = checkout scm
          env.GIT_COMMIT = scmVars.GIT_COMMIT
          env.GIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          currentBuild.description = "commit ${env.GIT_SHORT}"
        }
      }
    }

    stage('Test') {
      // Run tests inside the same Node version the image uses; Jenkins itself has no Node.
      agent {
        docker {
          image 'node:22-alpine'
          reuseNode true
          args '-e HOME=/tmp'
        }
      }
      steps {
        dir('app') {
          sh 'npm ci'
          sh 'npm test -- --ci'      // fails the build if any test fails or coverage < 80%
        }
      }
      post {
        always {
          recordCoverage(tools: [[parser: 'COBERTURA', pattern: 'app/coverage/cobertura-coverage.xml']])
        }
      }
    }

    stage('Build') {
      steps {
        sh '''
          docker build \
            --build-arg BUILD_NUMBER="$BUILD_NUMBER" \
            --build-arg GIT_COMMIT="$GIT_COMMIT" \
            -t "$IMAGE:$BUILD_NUMBER" -t "$IMAGE:$GIT_SHORT" \
            app/
          docker image ls "$IMAGE" --format '{{.Repository}}:{{.Tag}}  {{.Size}}' | head -4
        '''
      }
    }
  }

  post {
    always {
      cleanWs()
    }
  }
}
