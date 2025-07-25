package com.atlassian.container.models;

import com.atlassian.container.EgressClient;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Collections;
import java.util.Map;

import static com.atlassian.container.api.ForgeIngressHeaders.INVOCATION_ID;

@RestController
public class WebTriggerPublishRealtimeEventEndpoint {
    private static final Logger log = LoggerFactory.getLogger(WebTriggerPublishRealtimeEventEndpoint.class);
    private final EgressClient egressClient;

    public WebTriggerPublishRealtimeEventEndpoint(EgressClient egressClient) {
        this.egressClient = egressClient;
    }

    @ResponseBody
    @PostMapping("/webtrigger/realtime")
    public Map<String, String> post(@RequestHeader(INVOCATION_ID) String invocationId) {
        final String payload = "Realtime message sent from the container service, id = " + invocationId;
        final ResponseEntity<JsonNode> egressResponse = egressClient.publishRealtimeMessage(invocationId, "forge-container-realtime-channel", payload);
        log.info("Published a realtime message: {}, with response: {}", payload, egressResponse);

        return Collections.singletonMap("message", payload);
    }
}
