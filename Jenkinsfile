pipeline {
  agent {
    kubernetes {
      yaml '''
          apiVersion: v1
          kind: Pod
          spec:
            serviceAccountName: jenkins-deployer
            containers:    
              - name: maven
                image: maven:3.9-eclipse-temurin-17
                command: ["sleep"]
                args: ["infinity"]
                resources:
                  requests:
                    memory: "1Gi"
                    cpu: "500m"
                  limits:
                    memory: "2Gi"
              - name: kaniko
                image: gcr.io/kaniko-project/executor:v1.23.2-debug
                command: ["/busybox/cat"]
                tty: true
                resources:
                  requests:
                    memory: "1Gi"
                    cpu: "500m"
                  limits:
                    memory: "2Gi"
              - name: trivy
                image: aquasec/trivy:0.58.0
                command: ["sleep"]
                args: ["infinity"]
                resources:
                  requests:
                    memory: "512Mi"
                  limits:
                    memory: "1Gi"
              - name: crane
                image: gcr.io/go-containerregistry/crane:debug
                command: ["/busybox/cat"]
                tty: true
              - name: kubectl
                image: alpine/k8s:1.31.2
                command: ["sleep"]
                args: ["infinity"]
          '''
      defaultContainer 'maven'
    }
  }

  environment {
    IMAGE_REPO = 'docker.io/nouraldeen152/petclinic'
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timeout(time: 45, unit: 'MINUTES')
  }

  stages {
    stage('Checkout') {
      steps {
        script {
          def scmVars = checkout scm
          env.IMAGE_TAG = scmVars.GIT_COMMIT.take(7)
          env.BUILD_TS = sh(script: "date -u +%Y%m%d-%H%M%S", returnStdout: true).trim()
        }
      }
    }

    stage('Compile') {
      steps {
        sh 'mvn -B clean compile'
      }
    }

    stage('Test') {
      steps {
        sh 'mvn -B test jacoco:report'
      }
      post {
        always {
          junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: true
          recordCoverage(tools: [[parser: 'JACOCO']])
        }
      }
    }

    stage('Package') {
      steps {
        sh 'mvn -B package -DskipTests'
        archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
      }
    }

    stage('Build Image') {
      steps {
        container('kaniko') {
          sh '''
            /kaniko/executor \
              --context=dir://${WORKSPACE} \
              --dockerfile=${WORKSPACE}/Dockerfile \
              --destination=${IMAGE_REPO}:${IMAGE_TAG} \
              --no-push \
              --tarPath=${WORKSPACE}/image.tar \
              --ignore-path=/product_uuid
          '''
        }
      }
    }

    stage('Trivy Scan') {
      steps {
        container('trivy') {
          sh '''
            trivy image --input ${WORKSPACE}/image.tar \
              --scanners vuln \
              --severity HIGH,CRITICAL \
              --ignore-unfixed \
              --exit-code 1 \
              --timeout 15m \
              --cache-dir /tmp/trivy
          '''
        }
      }
    }

    stage('Push Image') {
      steps {
        container('crane') {
          withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
              usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
            sh '''
              echo "$DH_PASS" | crane auth login index.docker.io -u "$DH_USER" --password-stdin
              crane push ${WORKSPACE}/image.tar ${IMAGE_REPO}:${IMAGE_TAG}
              crane tag ${IMAGE_REPO}:${IMAGE_TAG} ${BUILD_TS}
            '''
          }
        }
      }
    }
    stage('Deploy to Dev') {
      steps {
        container('kubectl') {
          sh '''
            kubectl apply -f k8s/dev/service.yaml
            sed "s|IMAGE_PLACEHOLDER|${IMAGE_REPO}:${IMAGE_TAG}|" k8s/dev/deployment.yaml | kubectl apply -f -
          '''
          script { env.DEPLOYED = 'true' }
          sh 'kubectl rollout status deployment/petclinic -n petclinic-dev --timeout=180s'
        }
      }
    }

    stage('Smoke Test') {
      steps {
        container('kubectl') {
          sh '''
            for i in 1 2 3 4 5 6; do
              wget -qO- petclinic.petclinic-dev.svc.cluster.local/actuator/health | grep -q '"status":"UP"' && exit 0
              sleep 10
            done
            echo "Smoke test failed"
            exit 1
          '''
        }
      }
    }
  }
  
  post {
    failure {
      script {
        if (env.DEPLOYED == 'true') {
          container('kubectl') {
            sh 'kubectl rollout undo deployment/petclinic -n petclinic-dev'
            sh 'kubectl rollout status deployment/petclinic -n petclinic-dev --timeout=120s'
          }
        }
      }
    }
  }
}