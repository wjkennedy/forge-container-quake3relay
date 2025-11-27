package com.atlassian.container;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClient;

@SpringBootApplication
public class JavaSpringServerApplication implements CommandLineRunner {

    public static void main(String[] args) {
        SpringApplication.run(JavaSpringServerApplication.class, args);
    }

    private final Logger log = LoggerFactory.getLogger(JavaSpringServerApplication.class);

    private final RestClient restClient = RestClient.create();

    @Override
    public void run(String... args) throws Exception {
        try {
            // This code snippet demonstrates how offline access can be used to perform operations during bootstrap.
            // Sleep for 5 seconds to wait for everything to be ready
            Thread.sleep(5000);
            log.info("Application started - running bootstrap code using offline access...");
            
            // Step 1: Make a request to retrieve all installations for app environment (GET /v0/installations)
            
            ResponseEntity<String> response = restClient.get()
                .uri(getProxyUrl() + "/v0/installations")
                .retrieve()
                .toEntity(String.class);
            log.info("Retrieved all installations for app environment: {}", response.getBody());

            // Step 2: Make a request to write a value to KVS on behalf of all installations (POST /forge/storage/kvs/v1/set)
            // Iterate over installations from response body
            final ObjectMapper objectMapperInstallationObject = new ObjectMapper();
            JsonNode installations = objectMapperInstallationObject.readTree(response.getBody());
            for (JsonNode installation : installations) {
                final String installationId = installation.get("id").asText();
                // Creates a ObjectNode with the key and value pair
                // { key: "installationId-<installationId>", value: "bootstrap job ran at <currentTime>" }
                final ObjectNode objectNodeSet = createKvsRequestObject(installationId);
                
                // Set authorization header to perform action on behalf of installation using offline access
                // "Forge installationId=<installationId>,as=app"
                restClient.post()
                    .uri(getProxyUrl() + "/forge/storage/kvs/v1/set")
                    .body(objectNodeSet)
                    .header("forge-proxy-authorization", "Forge installationId=" + installationId + ",as=app")
                    .retrieve()
                    .toEntity(String.class);
            }
        } catch (Exception e) {
            System.out.println("Couldn't complete bootstrap operation. Error: " + e.getMessage());
        }
    }

    private String getProxyUrl() {
        // read from environment variable
        String proxyUrl = System.getenv("FORGE_EGRESS_PROXY_URL");
        if (proxyUrl == null) {
            throw new RuntimeException("FORGE_EGRESS_PROXY_URL environment variable is not set");
        }
        return proxyUrl;
    }

    private ObjectNode createKvsRequestObject(String installationId) {
        String currentTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        final ObjectMapper kvsRequestObjectMapper = new ObjectMapper();
        log.info("Writing value to KVS for installationId: {}", installationId);
        log.info("Key: cool-bootstrap-job-installationId-{}", installationId);
        log.info("Value: My cool bootstrap job ran at {} using offline access", currentTime);
        return kvsRequestObjectMapper.createObjectNode()
            .put("key", "cool-bootstrap-job-installationId-" + installationId)
            .put("value", "My cool bootstrap job ran at " + currentTime + " using offline access");

    }
}
