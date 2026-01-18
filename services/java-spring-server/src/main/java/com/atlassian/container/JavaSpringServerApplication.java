package com.atlassian.container;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;

@SpringBootApplication
@EnableScheduling
public class JavaSpringServerApplication implements CommandLineRunner {

    static void main(String[] args) {
        SpringApplication.run(JavaSpringServerApplication.class, args);
    }

    private final Logger log = LoggerFactory.getLogger(JavaSpringServerApplication.class);
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final EgressClient egressClient;

    public JavaSpringServerApplication(EgressClient egressClient) {
        this.egressClient = egressClient;
    }

    // Local state to store installation ids for offline access requests
    private final AtomicInteger fetchInstallationIdCounter = new AtomicInteger(0);
    private final List<String> installationIds = new CopyOnWriteArrayList<>();

    @Override
    public void run(String... args) {
        try {
            // This code snippet demonstrates how offline access can be used to perform operations during bootstrap.
            // Sleep for 5 seconds to wait for everything to be ready
            Thread.sleep(5000);
            log.info("Application started - running bootstrap code using offline access...");

            // Step 1: Make a request to retrieve all installations for app environment (GET /v0/installations)
            final List<EgressClient.Installation> installations = egressClient.getInstallations();
            if (installations.isEmpty()) {
                throw new Exception("Could not fetch any installations for app environment, please install this app environment to execute the boostrap operation.");
            }
            log.info("Retrieved all installations for app environment: {}", installations);

            // Step 2: Make a request to write a value to KVS on behalf of all installations (POST /forge/storage/kvs/v1/set)
            for (EgressClient.Installation installation : installations) {
                final String installationId = installation.id();

                // Creates a ObjectNode with the key and value pair
                // { key: "installationId-<installationId>", value: "bootstrap job ran at <currentTime>" }
                final ObjectNode objectNodeSet = createKvsRequestObject(installationId);

                // Make the egress request using offline access
                egressClient.setValueToKvsUsingOfflineAccess(objectNodeSet, installationId);
            }

            // Step 3: Make an asUser request to /rest/api/3/myself using offline access
            final String accountId = System.getenv("OFFLINE_ACCESS_USER_IMPERSONATION_DEMO_ACCOUNT_ID");
            if (accountId == null || accountId.isEmpty() || accountId.equals("offline_access_user_impersonation_demo_account_id")) {
                log.info("OFFLINE_ACCESS_USER_IMPERSONATION_DEMO_ACCOUNT_ID environment variable is not set. Skipping making an asUserrequest to Jira myself API.");
            } else {
                final String installationId = installations.get(0).id();
                try {
                    log.info("Making an asUser request by calling the Jira myself API using installation id: {} and account id: {}", installationId, accountId);
                    final ResponseEntity<String> egressResponse = egressClient.getCurrentUserUsingOfflineAccess(installationId, accountId);
                    log.info("Received Jira myself API with status code: {}", egressResponse.getStatusCode());
                    log.info("Jira myself API response body: {}", egressResponse.getBody());
                } catch (Exception e) {
                    log.error("Failed to call the Jira myself API with error message: {}", e.getMessage());
                }
            }
        } catch (Exception e) {
            log.error("Couldn't complete bootstrap operation. Error: {}", e.getMessage());
        }
    }

    private ObjectNode createKvsRequestObject(String installationId) {
        final String currentTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        log.info("Writing value to KVS for installationId: {}", installationId);
        log.info("Key: cool-bootstrap-job-installationId-{}", installationId);
        log.info("Value: My cool bootstrap job ran at {} using offline access", currentTime);
        return objectMapper.createObjectNode()
                .put("key", "cool-bootstrap-job-installationId-" + installationId)
                .put("value", "My cool bootstrap job ran at " + currentTime + " using offline access");

    }

    // Publish a global realtime message every 15 seconds using offline access
    @Scheduled(fixedDelay = 15000)
    private void publishGlobalRealtimeMessages() {
        // 1. Re-fetch the installation ids every minute to ensure we have the latest list
        try {
            if (fetchInstallationIdCounter.get() % 4 == 0) {
                log.info("Fetching installation ids for scheduled realtime message publishing...");
                final List<EgressClient.Installation> installations = egressClient.getInstallations();
                if (installations.isEmpty()) {
                    final String errorMessage = "Could not fetch any installation ids for scheduled realtime message publishing";
                    throw new Exception(errorMessage);
                } else {
                    installationIds.clear();
                    installationIds.addAll(installations.stream().map(EgressClient.Installation::id).toList());
                }
                fetchInstallationIdCounter.set(0);
            }
        } catch (Exception e) {
            log.error("Error fetching installation ids for scheduled realtime message publishing: {}", e.getMessage());
        }
        fetchInstallationIdCounter.incrementAndGet();

        // 2. Iterate over installation ids and publish a global realtime message using offline access
        for (final String installationId : installationIds) {
            try {
                log.info("Publishing a global realtime message for installation id {}...", installationId);

                final String messageString = "Offline access global realtime message sent at " +
                        LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

                egressClient.publishGlobalRealtimeMessageUsingOfflineAccess("offline-access-global-realtime-channel", messageString, installationId);
            } catch (Exception e) {
                log.error("Failed to publish scheduled realtime message: {}", e.getMessage());
            }
        }
    }
}
