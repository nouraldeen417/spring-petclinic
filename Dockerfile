# ---------- Stage 1: build ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Cache dependencies
COPY pom.xml .
RUN mvn -B dependency:go-offline

# Build the jar
COPY src ./src
RUN mvn -B clean package -DskipTests

# Extract Spring Boot layers
RUN java -Djarmode=tools -jar target/*.jar extract --layers --destination extracted

# ---------- Stage 2: run ----------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Update OS packages to pick up security fixes
RUN apk upgrade --no-cache

# Non-root user
RUN addgroup -S app && adduser -S app -G app
USER app

# Copy layers: least changing first
COPY --from=build /app/target/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]