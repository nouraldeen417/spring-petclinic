# Stage 1: prepare layers from the jar the pipeline already built
FROM eclipse-temurin:17-jre-alpine AS extract
WORKDIR /app
COPY dist/app.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --destination extracted

# ---------- Stage 2: run ----------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Update OS packages to pick up security fixes
RUN apk upgrade --no-cache

# Non-root user
RUN addgroup -S app && adduser -S app -G app
USER app

# Copy layers: least changing first
COPY --from=extract /app/target/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]