package com.atlassian.container;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

import static com.atlassian.container.api.ForgeIngressHeaders.*;

@RestController
public class InvokeServiceEndpoint {

    private static final Logger log = LoggerFactory.getLogger(InvokeServiceEndpoint.class);

    @PostMapping("/invoke-service")
    public ResponseEntity<Map<String, Object>> post(@RequestHeader Map<String, String> headers, @RequestHeader(INVOCATION_ID) String invocationId, @RequestBody Object body) {
        log.info("Received invocationId: {}", invocationId);
        log.info("Received headers: {}", headers);
        log.info("Received body: {}", body);

        // set a custom header on the response
        HttpHeaders responseHeaders = new HttpHeaders();
        responseHeaders.set("x-custom-response-header", "x-custom-response-header-value");

        Map<String, Object> responseBody = new HashMap<>();
        responseBody.put("message", "Hello from invoke-service endpoint");

        // reflect the request details back in the response
        Map<String, Object> requestDetails = new HashMap<>();
        requestDetails.put("headers", headers);
        requestDetails.put("body", body);
        responseBody.put("requestDetails", requestDetails);

        return new ResponseEntity<>(responseBody, responseHeaders, HttpStatus.OK);
    }
}
