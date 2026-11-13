// Number Guessing Game pipeline
pipeline {
  agent any

  triggers {
    githubPush()
  }

  options {
    skipDefaultCheckout()          // we check out explicitly in the 'Checkout' stage
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 20, unit: 'MINUTES')
  }

  environment {
    IMAGE = "${env.DOCKERHUB_USER}/guessgame"
  }

  stages {
    stage('Checkout') {
      steps {
        script {
          // With skipDefaultCheckout, GIT_COMMIT is not set automatically
          def scmVars = checkout scm
          env.GIT_COMMIT = scmVars.GIT_COMMIT
          env.GIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          currentBuild.description = "commit ${env.GIT_SHORT}"
        }
      }
    }

    stage('Test') {
      // Run tests inside the same Node version the image uses
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
          sh 'npm test -- --ci'
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
        '''
      }
    }

    stage('Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
          sh '''
            echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
            docker push -q "$IMAGE:$BUILD_NUMBER"
            docker push -q "$IMAGE:$GIT_SHORT"
          '''
        }
      }
      post {
        always { sh 'docker logout >/dev/null 2>&1 || true' }   // don't leave the token on disk
      }
    }

    stage('Deploy Test') {
      steps {
        sshagent(credentials: ['deploy-ssh']) {
          sh 'cat deploy/lib.sh deploy/deploy-test.sh | ssh deploy@"$TEST_HOST" sh -s -- "$IMAGE:$BUILD_NUMBER"'
        }
      }
    }

    stage('Smoke Test') {
      steps {
        // Plays a real game against the test server
        sh 'sh deploy/smoke-test.sh "http://$TEST_HOST:3000" "$BUILD_NUMBER" full'
      }
    }

    stage('Deploy Prod') {
      // Blue-green deploy
      steps {
        sshagent(credentials: ['deploy-ssh']) {
          sh 'cat deploy/lib.sh deploy/deploy-prod.sh | ssh deploy@"$PROD_HOST" sh -s -- "$IMAGE:$BUILD_NUMBER" "$BUILD_NUMBER" "$GIT_SHORT"'
        }
      }
    }

    stage('Verify') {
      steps {
        // Checks the PUBLIC URL through Nginx
        sh 'sh deploy/smoke-test.sh "$PROD_PUBLIC_URL" "$BUILD_NUMBER" readonly'
      }
    }
  }

  post {
    failure {
      echo "Pipeline FAILED. Production was not changed by this build (see the failed stage above)."
    }
    success {
      echo "Live: ${env.PROD_PUBLIC_URL} (build #${env.BUILD_NUMBER}, commit ${env.GIT_SHORT})"
    }
    always {
      // Images are on Docker Hub now
      sh 'docker image rm "$IMAGE:$BUILD_NUMBER" "$IMAGE:$GIT_SHORT" >/dev/null 2>&1 || true'
      cleanWs()
    }
  }
}
