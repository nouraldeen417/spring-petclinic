// =============================================================================
// PetClinic CI/CD pipeline (Jenkins declarative pipeline)
//
// Flow:
//   checkout -> settings -> version -> compile -> test -> quality gate -> publish
//   jar -> fetch jar -> build image -> scan -> push -> deploy dev -> smoke test
//   -> manual approval -> deploy staging -> smoke test
//
// Design rules
//   1. Thin Jenkinsfile. The logic lives in the shared library (vars/*.groovy).
//      This file says WHAT runs and in WHICH pod.
//   2. agent none at the top. Each group of work gets its own short-lived pod,
//      with only the tools it needs. The approval step has no pod.
//   3. Pods do not share a disk. The jar travels through Nexus, and every pod
//      checks out the code again, proving it is the same commit.
//
// Pods (library: resources/pods/)
//   maven.yaml   Build and Analyze   maven
//   image.yaml   Package Image       tools, kaniko, trivy, crane
//   deploy.yaml  Deploy Dev/Staging  kubectl (ServiceAccount jenkins-deployer)
//
// Where values come from
//   environment block below   per-app values (not secrets)
//   library defaults          container names, default credential IDs, flags
//   Jenkins global settings   NEXUS_URL
//   Jenkins credentials       dockerhub-creds, sonar-cloud-token, nexus-ci
//   set while building        IMAGE_TAG, BUILD_TS, ART_VERSION, ART_URL
//
// Prerequisites that live OUTSIDE Git (create them before the first run)
//   - Jenkins credentials: dockerhub-creds, sonar-cloud-token, nexus-ci
//   - Jenkins managed file: maven-settings (Config File Provider)
//   - Jenkins global environment variable: NEXUS_URL
//   - Cluster: platform/ files applied, RBAC applied
//   - Staging database and its Secret, created by hand:
//     see platform/staging-db/README.md
// =============================================================================

// Pinned to main while developing. For a stable release, use a tag, for
// example @v1.0.0, so a library change cannot break this pipeline by surprise.
@Library('petclinic-shared-library@main') _

pipeline {
  // No pod at the top. Each stage below asks for its own pod.
  agent none

  // Per-app values. None of these is a secret.
  environment {
    IMAGE_REPO = 'docker.io/nouraldeen152/petclinic'
    SONAR_ORG  = 'nouraldeen417'
    SONAR_PROJECT = 'nouraldeen417_spring-petclinic'
  }

  options {
    // checkoutSource() checks the code out explicitly and verifies the commit,
    // so the automatic checkout is turned off.
    skipDefaultCheckout(true)
    // Time in front of every log line, to see which step is slow.
    timestamps()
    // Keep only the last 10 builds, to save disk.
    buildDiscarder(logRotator(numToKeepStr: '10'))
    // Total limit. It includes the time spent waiting at the approval.
    timeout(time: 90, unit: 'MINUTES')
  }

  stages {

    // ---- Pod 1: maven. Build, test, analyse, store the jar -----------------
    stage('Build and Analyze') {
      agent { kubernetes { yaml libraryResource('pods/maven.yaml'); defaultContainer 'maven' } }
      steps {
        script {
          // The first 7 characters of the commit are the image tag. The date
          // and time (UTC) is the second tag, for people to read.
          env.IMAGE_TAG = checkoutSource().take(7)
          env.BUILD_TS  = sh(script: 'date -u +%Y%m%d-%H%M%S', returnStdout: true).trim()
        }
        // Make Maven download through Nexus. The pod is new, so this runs every build.
        mavenSettings()
        script {
          // Work out the jar version and its Nexus address ONCE. It must run
          // before publishJar, because publishJar changes pom.xml.
          def art = artifactInfo(tag: env.IMAGE_TAG)
          env.ART_VERSION = art.version
          env.ART_URL     = art.url
        }
        sh 'mvn -B clean compile'
        // Tests and the coverage report. Reports are recorded even when tests fail.
        mavenTest()
        // Quality gate. It needs the coverage report from the step above.
        sonarScan(org: env.SONAR_ORG, project: env.SONAR_PROJECT)
        // Upload the jar to Nexus. It is skipped if this version already exists.
        publishJar(version: env.ART_VERSION, url: env.ART_URL)
      }
    }

    // ---- Pod 2: image tools. Build, scan, push (the tar file stays in this pod)
    stage('Package Image') {
      agent { kubernetes { yaml libraryResource('pods/image.yaml'); defaultContainer 'tools' } }
      steps {
        // Same commit as the first pod, or the build stops.
        checkoutSource(expectedTag: env.IMAGE_TAG)
        // Download the jar that was stored in Nexus. The Dockerfile copies it.
        fetchJar(url: env.ART_URL)
        // Build and save as a tar. Nothing is pushed yet.
        buildImage(repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG)
        // Fails the build on fixable HIGH or CRITICAL findings, before the push.
        scanImage()
        // Only a scanned image reaches Docker Hub. Two tags: SHA and date-time.
        pushImage(repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG, timeStamp: env.BUILD_TS)
      }
    }

    // ---- Pod 3: kubectl. Deploy to dev, then check it ----------------------
    stage('Deploy Dev') {
      agent { kubernetes { yaml libraryResource('pods/deploy.yaml'); defaultContainer 'kubectl' } }
      steps {
        checkoutSource(expectedTag: env.IMAGE_TAG)
        // Applies k8s/dev/*.yaml, waits for the rollout. On failure it rolls
        // back by itself and the build stays red.
        deployToK8s(namespace: 'petclinic-dev', manifestDir: 'k8s/dev',
                    repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG)
        // Health check, plus a data check (an owner from the sample data).
        // On failure it also rolls back.
        smokeTest(namespace: 'petclinic-dev',
                  dataPath: '/owners?lastName=Franklin', dataExpect: 'Franklin')
      }
    }

    // ---- No pod: waiting for a person costs no memory ----------------------
    stage('Approve Staging') {
      steps { approve(message: 'Promote this image to staging?') }
    }

    // ---- Pod 4: a new kubectl pod. Same image tag, nothing is rebuilt ------
    stage('Deploy Staging') {
      agent { kubernetes { yaml libraryResource('pods/deploy.yaml'); defaultContainer 'kubectl' } }
      steps {
        checkoutSource(expectedTag: env.IMAGE_TAG)
        // PREREQUISITE: the Postgres StatefulSet and the Secret petclinic-db
        // exist in petclinic-staging. They are created BY HAND, outside this
        // pipeline (see platform/staging-db/README.md). This step applies only
        // the app files (k8s/staging).
        deployToK8s(namespace: 'petclinic-staging', manifestDir: 'k8s/staging',
                    repoUrl: env.IMAGE_REPO, tag: env.IMAGE_TAG)
        smokeTest(namespace: 'petclinic-staging',
                  dataPath: '/owners?lastName=Franklin', dataExpect: 'Franklin')
      }
    }
  }
}