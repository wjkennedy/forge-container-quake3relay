package com.atlassian.container;

import com.atlassian.container.exceptions.KvsResponseException;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

import static com.atlassian.container.api.ForgeIngressHeaders.INVOCATION_ID;

@RestController
public class ScheduledTriggerEndpoint {

    private static final Logger log = LoggerFactory.getLogger(ScheduledTriggerEndpoint.class);
    private final EgressClient egressClient;
    private final String executionTimeKvsKey = "currentExecutionTime";

    public ScheduledTriggerEndpoint(EgressClient egressClient) {
        this.egressClient = egressClient;
    }

    @PostMapping("/scheduled-trigger")
    @ResponseStatus(HttpStatus.OK)
    public void scheduledTrigger(@RequestHeader(INVOCATION_ID) String invocationId) {
        log.info("Performing scheduled trigger invocation");

        String currentTime = Long.toString(System.currentTimeMillis());
        log.warn("Saving latest scheduled trigger time in KVS under key: {}", executionTimeKvsKey);
        ResponseEntity<JsonNode> setKvsResponse = egressClient.setValueToKvs(invocationId, executionTimeKvsKey, currentTime);

        log.info("Received Set KVS response: {}", setKvsResponse);
    }

    @GetMapping("/latest-scheduled-trigger-time")
    @ResponseStatus(HttpStatus.OK)
    public Map<String, Long> latestScheduledTriggerTime(@RequestHeader(INVOCATION_ID) String invocationId) {
        log.info("Retrieving latest scheduled trigger invocation time");

        ResponseEntity<JsonNode> getKvsResponse = egressClient.getValueFromKvs(invocationId, executionTimeKvsKey);
        log.info("Received Get KVS response: {}", getKvsResponse);

        JsonNode kvsResponseBody = getKvsResponse.getBody();
        if (kvsResponseBody == null) {
            throw new KvsResponseException("No response body from KVS for key: " + executionTimeKvsKey);
        }

        return Map.of("currentExecutionTime", kvsResponseBody.get("value").asLong());
    }
}
