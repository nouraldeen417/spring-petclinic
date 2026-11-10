# =============================================================================
# PetClinic runtime image
#
# Input : dist/app.jar. The pipeline downloads it from Nexus (stage Package
#         Image, step fetchJar). This Dockerfile never builds the application.
# Output: a small image that runs the jar as a non-root user.
# Built by Kaniko in the image pod. It does not push; scanImage and pushImage
# use the tar file Kaniko writes.
# Local test: put a jar at dist/app.jar, then run docker build.
#
# Design choice: one stage. Building and testing happen in the pipeline, so the
# image only needs a runtime and the jar. Trade-off: the whole jar is one image
# layer, so every code change rebuilds that layer. Spring Boot layered jars
# would avoid this (see docs/decisions.md).
# =============================================================================

# JRE only: no JDK, no Maven, no source code. A smaller image has fewer
# packages, so it has fewer vulnerabilities for Trivy to find.
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Pick up the latest OS security fixes. Side effect: two builds of the same
# commit on different days can differ slightly. The base tag is also a floating
# tag; pin an exact tag for fully repeatable builds.
RUN apk upgrade --no-cache

# Run as a normal user, not root (least privilege). -S makes a system user
# with no login.
RUN addgroup -S app && adduser -S app -G app
USER app

# dist/app.jar is a path in the build context (the pipeline workspace).
# --chown is not needed: the app only reads the jar.
COPY dist/app.jar app.jar

# Documentation only. It does not publish the port; the Kubernetes Service does.
EXPOSE 8080

# MaxRAMPercentage=75: the JVM heap may use 75 percent of the container memory
# limit, which leaves room for non-heap memory. Without it, a JVM can be killed
# for exceeding the limit.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]