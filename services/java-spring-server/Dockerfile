# Build stage
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /workspace/app

COPY . .
RUN ./gradlew bootJar

# Run stage
FROM eclipse-temurin:21-jre-jammy

WORKDIR /opt/service
COPY --from=builder /workspace/app/build/libs/java-spring-server-*.jar /opt/service/service.jar

EXPOSE 8080
CMD ["java", "-jar", "/opt/service/service.jar"]