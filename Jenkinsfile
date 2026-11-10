// SWE40006 Group 4 — Number Guessing Game pipeline.
// Checkout -> Test -> Build -> Push -> Deploy Test -> Smoke Test -> Deploy Prod -> Verify
// Any failing stage stops the pipeline, so a broken build never reaches production.
pipeline {
  agent any

  triggers {
    githubPush()                   // Level 4: GitHub webhook on push to main starts a build
  }

  options {
    skipDefaultCheckout()          // we check out explicitly in the 'Checkout' stage
    timestamps()
    disableConcurrentBuilds()      // one deployment at a time
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 20, unit: 'MINUTES')
  }

  environment {
    IMAGE = "${env.DOCKERHUB_USER}/guessgame"   // DOCKERHUB_USER, TEST_HOST, PROD_HOST, PROD_PUBLIC_URL come from JCasC
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
        // Plays a real game against the test server (new game, guesses, win, score), not just /health.
        sh 'sh deploy/smoke-test.sh "http://$TEST_HOST:3000" "$BUILD_NUMBER" full'
      }
    }

    stage('Deploy Prod') {
      // Blue-green: new colour starts beside the live one, is health-checked (12 x 5 s), then Nginx
      // switches over. If the health check fails the script exits 1 and production is untouched.
      steps {
        sshagent(credentials: ['deploy-ssh']) {
          sh 'cat deploy/lib.sh deploy/deploy-prod.sh | ssh deploy@"$PROD_HOST" sh -s -- "$IMAGE:$BUILD_NUMBER" "$BUILD_NUMBER" "$GIT_SHORT"'
        }
      }
    }

    stage('Verify') {
      steps {
        // Checks the PUBLIC URL through Nginx. Read-only mode never wins, so real best scores are safe.
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
      // Images are on Docker Hub now; drop local copies so VM1's disk doesn't fill up.
      sh 'docker image rm "$IMAGE:$BUILD_NUMBER" "$IMAGE:$GIT_SHORT" >/dev/null 2>&1 || true'
      cleanWs()
    }
  }
}
