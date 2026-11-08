@Library('petclinic-shared-library@main') _
pipeline {
  agent {
    kubernetes {
      yaml libraryResource('pods/ci.yaml')
      defaultContainer 'maven'
    }
  }

  environment {
    IMAGE_REPO = 'docker.io/nouraldeen152/petclinic'
    SONAR_ORG  = 'nouraldeen417'
    SONAR_PROJECT = 'nouraldeen417_spring-petclinic'
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

    stage('Maven Settings') {
      steps { mavenSettings() }
    }

    stage('Compile') {
      steps {
        sh 'mvn -B clean compile'
      }
    }

    stage('Test') {
      steps { mavenTest() }
    }

    stage('SonarQube Cloud') {
      steps { sonarScan(org: env.SONAR_ORG, project: env.SONAR_PROJECT) }
    }

    stage('Compute Version') {
      steps {
        script {
          def art = artifactInfo(tag: env.IMAGE_TAG)
          env.ART_VERSION = art.version
          env.ART_URL     = art.url
        }
      }
    }

    stage('Publish Jar') {
      steps { publishJar(version: env.ART_VERSION, url: env.ART_URL) }
    }

    stage('Fetch Jar') {
      steps { fetchJar(url: env.ART_URL) }
    }

    stage('Build Image') { 
      steps { buildImage(repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG) } 
    }
    
    stage('Trivy Scan')  { 
      steps { scanImage() }
    }
    
    stage('Push Image')  { 
      steps { pushImage(repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG, timeStamp: env.BUILD_TS) } 
    }
    
    stage('Deploy to Dev') {
      steps {
        deployToK8s(namespace: 'petclinic-dev', manifestDir: 'k8s/dev',
                    repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG)
      }
    }

    stage('Smoke Test Dev') {
      steps {
        smokeTest(namespace: 'petclinic-dev',
                  dataPath: '/owners?lastName=Franklin', dataExpect: 'Franklin')
      }
    }

    stage('Approve Staging') {
      steps { approve(message: 'Promote this image to staging?') }
    }

    stage('Deploy to Staging') {
      steps {
        deployToK8s(namespace: 'petclinic-staging', manifestDir: 'k8s/staging',
                    repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG)
      }
    }

    stage('Smoke Test Staging') {
      steps {
        smokeTest(namespace: 'petclinic-staging',
                  dataPath: '/owners?lastName=Franklin', dataExpect: 'Franklin')
      }
    }
  }
  
}