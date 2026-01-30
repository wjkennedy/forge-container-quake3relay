# Build stage
FROM eclipse-temurin:25-jdk AS builder
WORKDIR /workspace/app

COPY . .
RUN ./gradlew bootJar

# Run stage
FROM eclipse-temurin:25-jre-jammy

RUN useradd -u 1000 -r -s /bin/false appuser

WORKDIR /opt/service
COPY --from=builder /workspace/app/build/libs/java-spring-server-*.jar /opt/service/service.jar

EXPOSE 8080
USER appuser
CMD ["java", "-XX:InitialRAMPercentage=15", "-XX:MaxRAMPercentage=35", "-jar", "/opt/service/service.jar"]
