# Build stage
FROM eclipse-temurin:21.0.8_9-jdk@sha256:1f3171966c0ca6b7151c56059bc70c40d3b880b4333feb91d5b09a68f159af3b AS builder
WORKDIR /workspace/app

COPY . .
RUN ./gradlew bootJar

# Run stage
FROM eclipse-temurin:21.0.8_9-jre-jammy@sha256:080ee1e167a9c858444a39c29be49f5a43bca81ea47aa2a6172fc04c987062c6

WORKDIR /opt/service
COPY --from=builder /workspace/app/build/libs/java-spring-server-*.jar /opt/service/service.jar

EXPOSE 8080
CMD ["java", "-jar", "/opt/service/service.jar"]