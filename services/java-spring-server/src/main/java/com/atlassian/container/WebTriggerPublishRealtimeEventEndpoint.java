package com.atlassian.container;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

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
    private final ObjectMapper objectMapper;

    public WebTriggerPublishRealtimeEventEndpoint(EgressClient egressClient) {
        this.egressClient = egressClient;
        this.objectMapper = new ObjectMapper();
    }

    @ResponseBody
    @PostMapping("/webtrigger/realtime/global")
    public Map<String, String> publishGlobalMessage(@RequestHeader(INVOCATION_ID) String invocationId) {
        final String payload = "Global realtime message sent from the container service, id = " + invocationId;
        final ResponseEntity<JsonNode> egressResponse = egressClient.publishGlobalRealtimeMessage(invocationId,
                "forge-container-global-realtime-channel", payload, 
                null);
        log.info("Published a global realtime message: {}, with response: {}", payload, egressResponse);

        return Collections.singletonMap("message", payload);
    }

    @ResponseBody
    @PostMapping("/webtrigger/realtime/token")
    public Map<String, String> signRealtimeTokenAndPublishGlobalMessage(@RequestHeader(INVOCATION_ID) String invocationId) {
        final String realtimeChannel = "forge-container-global-token-realtime-channel";
        final ObjectNode claims = objectMapper.createObjectNode();
        claims.putArray("allowedUsers")
                .add("accountId-1")
                .add("accountId-2");

        final ResponseEntity<JsonNode> egressResponse = egressClient.signRealtimeToken(invocationId,
                realtimeChannel, claims);
        log.info("Signed a realtime token for channelName: {}, and claims {}, with response: {}", realtimeChannel, claims, egressResponse);

        final JsonNode jwtNode = egressResponse.getBody().path("token");
        final String signedRealtimeToken = jwtNode.asText();

        final String payload = "Realtime token signed and global message sent from the container service using a token, id = " + invocationId;
        final ResponseEntity<JsonNode> publishResponse = egressClient.publishGlobalRealtimeMessage(invocationId,
                realtimeChannel,
                payload,
                signedRealtimeToken);
        log.info("Published a global realtime message using a signed token to channel: {}, with response: {}", realtimeChannel, publishResponse);

        return Collections.singletonMap("message", payload);
    }
}
