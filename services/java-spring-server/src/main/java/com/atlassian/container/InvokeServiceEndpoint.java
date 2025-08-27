package com.atlassian.container;

import java.util.HashMap;
import java.util.Map;

import com.atlassian.container.exceptions.EgressRequestException;
import com.atlassian.container.models.User;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import com.atlassian.container.EgressClient.AuthType;

import static com.atlassian.container.api.ForgeIngressHeaders.INVOCATION_ID;

@RestController
public class InvokeServiceEndpoint {

    private static final Logger log = LoggerFactory.getLogger(InvokeServiceEndpoint.class);
    private final EgressClient egressClient;
    private final ObjectMapper objectMapper;

    public InvokeServiceEndpoint(EgressClient egressClient) {
        this.egressClient = egressClient;
        this.objectMapper = new ObjectMapper();
    }

    @PostMapping("/invoke-service")
    public ResponseEntity<Map<String, Object>> post(@RequestHeader Map<String, String> headers,
                                                    @RequestHeader(INVOCATION_ID) String invocationId,
                                                    @RequestBody Object body,
                                                    @RequestParam(required = false) String exampleStr,
                                                    @RequestParam(required = false) Integer exampleInt) {
        log.info("Received invocationId: {}", invocationId);
        log.info("Received headers: {}", headers);
        log.info("Received body: {}", body);
        log.info("Received query parameters: exampleStr={}, exampleInt={}", exampleStr, exampleInt);
        log.info("Read forge environment variable FORGE_REFERENCE_APP_KEY={}", System.getenv("FORGE_REFERENCE_APP_KEY"));

        // set a custom header on the response
        HttpHeaders responseHeaders = new HttpHeaders();
        responseHeaders.set("x-custom-response-header", "x-custom-response-header-value");

        // set the response body
        Map<String, Object> responseBody = new HashMap<>();
        responseBody.put("message", "Hello from invoke-service endpoint");

        // call a Product API asApp and asUser and add to the response
        addCurrentUserToResponseBody(AuthType.app, invocationId, responseBody);
        addCurrentUserToResponseBody(AuthType.user, invocationId, responseBody);

        // reflect the request details back in the response
        Map<String, Object> requestDetails = new HashMap<>();
        requestDetails.put("headers", headers);
        requestDetails.put("body", body);
        requestDetails.put("queryParameters", Map.of(
                "exampleStr", exampleStr,
                "exampleInt", exampleInt
        ));
        responseBody.put("requestDetails", requestDetails);

        return new ResponseEntity<>(responseBody, responseHeaders, HttpStatus.OK);
    }

    private void addCurrentUserToResponseBody(AuthType authType, String invocationId, Map<String, Object> responseBody) {
        try {
            ResponseEntity<JsonNode> currentUserResp = egressClient.getCurrentUser(invocationId, authType);
            log.info("Get current user from Jira API ({}) response: {}", authType, currentUserResp);

            User user = this.objectMapper.treeToValue(currentUserResp.getBody(), User.class);
            responseBody.put(authType + "CurrentUser", user);
        } catch (EgressRequestException egressErr) {
            log.error("Request failed with error: ", egressErr);
        } catch (JsonProcessingException parseErr) {
            log.error("Parsing response failed with error: ", parseErr);
        }
    }
}
