package com.atlassian.container;

import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import com.fasterxml.jackson.databind.node.ObjectNode;

import static com.atlassian.container.api.ForgeIngressHeaders.INVOCATION_ID;

import java.util.HashMap;
import java.util.Map;

@RestController
public class RealtimeEndpoint {

        private static final Logger log = LoggerFactory.getLogger(RealtimeEndpoint.class);
        private final EgressClient egressClient;

        public RealtimeEndpoint(EgressClient egressClient) {
                this.egressClient = egressClient;
        }

        /**
         * This endpoint is called from frontend invokeService to sign a realtime token.
         * This token can then be passed into the realtime.subscribe[Global] method.
         */
        @PostMapping("/sign-realtime-token")
        public ResponseEntity<Map<String, Object>> signRealtimeToken(@RequestHeader(INVOCATION_ID) String invocationId,
                        @RequestBody JsonNode body) {

                String channelName = body.path("channelName").asText();
                ObjectNode claims = (ObjectNode) body.path("claims");

                log.info("Signing realtime token with channelName {}, and claims {}", channelName,
                                claims.toString());

                final ResponseEntity<JsonNode> egressResponse = egressClient.signRealtimeToken(invocationId,
                                channelName,
                                claims);

                final JsonNode jwtNode = egressResponse.getBody().path("token");
                final String signedRealtimeToken = jwtNode.asText();
                String tokenPreview = signedRealtimeToken.length() > 12 
                        ? signedRealtimeToken.substring(0, 6) + "..." + signedRealtimeToken.substring(signedRealtimeToken.length() - 6)
                        : signedRealtimeToken;
                log.info("Extracted jwt in /sign-realtime-token invokeService endpoint: {}", tokenPreview);

                HttpHeaders responseHeaders = new HttpHeaders();
                responseHeaders.set("x-custom-response-header", "x-custom-response-header-value");

                // Put the Signed Realtime Token JWT into the response body
                Map<String, Object> responseBody = new HashMap<>();
                responseBody.put("signedRealtimeToken", signedRealtimeToken);

                return new ResponseEntity<>(responseBody, responseHeaders, HttpStatus.OK);
        }

        /**
         * This endpoint is called from frontend invokeService to publish a message to a
         * non global channel.
         */
        @PostMapping("/publish-realtime-message")
        public ResponseEntity<Map<String, Object>> publishRealtimeMessage(
                        @RequestHeader(INVOCATION_ID) String invocationId,
                        @RequestBody JsonNode body) {

                String channelName = body.path("channelName").asText();
                log.info("Publishing a realtime message to a non global channel with channelName {}", channelName);

                final String payload = "Realtime message sent from the container service invoked from the frontend, id = "
                                + invocationId;
                final ResponseEntity<JsonNode> egressResponse = egressClient.publishRealtimeMessage(invocationId,
                                channelName, payload, null, null);

                HttpHeaders responseHeaders = new HttpHeaders();
                responseHeaders.set("x-custom-response-header", "x-custom-response-header-value");

                Map<String, Object> responseBody = new HashMap<>();
                responseBody.put("publishedMessage", egressResponse.getBody());

                return new ResponseEntity<>(responseBody, responseHeaders, HttpStatus.OK);
        }
}
