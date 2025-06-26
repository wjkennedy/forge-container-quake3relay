# Build stage
FROM eclipse-temurin:21.0.7_6-jdk@sha256:2cc80b4288f6240734ecd1acae01d20afa56f86327b9ae207a9468363422c974 AS builder
WORKDIR /workspace/app

COPY . .
RUN ./gradlew bootJar

# Run stage
FROM eclipse-temurin:21.0.7_6-jre-jammy@sha256:034ce51c134cb9abcf28e2bda88fa36ac51369bb26351d697297e81caa9a5d76

WORKDIR /opt/service
COPY --from=builder /workspace/app/build/libs/java-spring-server-*.jar /opt/service/service.jar

EXPOSE 8080
CMD ["java", "-jar", "/opt/service/service.jar"]