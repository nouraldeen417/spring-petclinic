@Library('petclinic-shared-library@main') _

pipeline {
  agent none

  environment {
    IMAGE_REPO = 'docker.io/nouraldeen152/petclinic'
    SONAR_ORG  = 'nouraldeen417'
    SONAR_PROJECT = 'nouraldeen417_spring-petclinic'
  }

  options {
    skipDefaultCheckout(true)
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timeout(time: 90, unit: 'MINUTES')
  }

  stages {

    stage('Build and Analyze') {
      agent { kubernetes { yaml libraryResource('pods/maven.yaml'); defaultContainer 'maven' } }
      steps {
        script {
          env.IMAGE_TAG = checkoutSource().take(7)
          env.BUILD_TS  = sh(script: 'date -u +%Y%m%d-%H%M%S', returnStdout: true).trim()
        }
        mavenSettings()
        script {
          def art = artifactInfo(tag: env.IMAGE_TAG)
          env.ART_VERSION = art.version
          env.ART_URL     = art.url
        }
        sh 'mvn -B clean compile'
        mavenTest()
        sonarScan(org: env.SONAR_ORG, project: env.SONAR_PROJECT)
        publishJar(version: env.ART_VERSION, url: env.ART_URL)
      }
    }

    stage('Package Image') {
      agent { kubernetes { yaml libraryResource('pods/image.yaml'); defaultContainer 'tools' } }
      steps {
        checkoutSource(expectedTag: env.IMAGE_TAG)
        fetchJar(url: env.ART_URL)
        buildImage(repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG)
        scanImage()
        pushImage(repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG, timeStamp: env.BUILD_TS)
      }
    }

    stage('Deploy Dev') {
      agent { kubernetes { yaml libraryResource('pods/deploy.yaml'); defaultContainer 'kubectl' } }
      steps {
        checkoutSource(expectedTag: env.IMAGE_TAG)
        deployToK8s(namespace: 'petclinic-dev', manifestDir: 'k8s/dev',
                    repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG)
        smokeTest(namespace: 'petclinic-dev',
                  dataPath: '/owners?lastName=Franklin', dataExpect: 'Franklin')
      }
    }

    stage('Approve Staging') {
      steps { approve(message: 'Promote this image to staging?') }
    }

    stage('Deploy Staging') {
      agent { kubernetes { yaml libraryResource('pods/deploy.yaml'); defaultContainer 'kubectl' } }
      steps {
        checkoutSource(expectedTag: env.IMAGE_TAG)
        deployToK8s(namespace: 'petclinic-staging', manifestDir: 'k8s/staging',
                    repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG)
        smokeTest(namespace: 'petclinic-staging',
                  dataPath: '/owners?lastName=Franklin', dataExpect: 'Franklin')
      }
    }
  }
}