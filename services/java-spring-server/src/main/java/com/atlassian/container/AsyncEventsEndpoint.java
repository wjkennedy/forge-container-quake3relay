package com.atlassian.container;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

import static com.atlassian.container.api.ForgeIngressHeaders.INVOCATION_ID;
import static java.util.Collections.singletonList;
import static java.util.Collections.singletonMap;

import java.io.IOException;

@RestController
@RequestMapping("async-events")
public class AsyncEventsEndpoint {

    private static final Logger log = LoggerFactory.getLogger(AsyncEventsEndpoint.class);
    private static final String KVS_KEY = AsyncEventsEndpoint.class.getSimpleName();
    private static final String QUEUE_NAME = "test-async-event-queue";

    private final EgressClient egressClient;

    public AsyncEventsEndpoint(EgressClient egressClient) {
        this.egressClient = egressClient;
    }

    @ResponseBody
    @PostMapping("/publish")
    public Map<String, String> publishEvent(@RequestHeader(INVOCATION_ID) String invocationId,
            @RequestBody JsonNode body) {

        log.info("Publishing event for invocationId={}, body={}", invocationId, body);
        log.info("Result: {}", egressClient.queueAsyncEvent(invocationId, AsyncEventsEndpoint.QUEUE_NAME,
                singletonList(new EgressClient.AsyncEvent(new EgressClient.AsyncEvent.Body(body)))));

        return singletonMap("message", "Queued event for processing");
    }

    @ResponseBody
    @PostMapping("/handle")
    public Map<String, String> handleEvent(@RequestHeader(INVOCATION_ID) String invocationId, @RequestBody JsonNode event) {
        log.info("Storing async event for invocationId={}, event={}", invocationId, event);

        ResponseEntity<JsonNode> kvsResponse = egressClient.setValueToKvs(invocationId, AsyncEventsEndpoint.KVS_KEY, event.get("body").get("payload").toString());
        log.info("KVS result: {}", kvsResponse);

        return singletonMap("message", "Event handled");
    }

    @ResponseBody
    @GetMapping("/latest")
    public JsonNode getLatestEvent(@RequestHeader(INVOCATION_ID) String invocationId) throws IOException {

        log.info("Retrieving latest stored async event for invocationId={}", invocationId);

        ResponseEntity<JsonNode> kvsResponse = egressClient.getValueFromKvs(invocationId, AsyncEventsEndpoint.KVS_KEY);
        log.info("KVS result: {}", kvsResponse);

        return new ObjectMapper().readTree(kvsResponse.getBody().get("value").asText());
    }
}
