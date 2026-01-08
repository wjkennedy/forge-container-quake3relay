package com.atlassian.container;

import com.atlassian.container.EgressClient.AuthType;
import com.atlassian.container.db.Book;
import com.atlassian.container.db.BookRepository;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.Map;
import java.util.Optional;

import static com.atlassian.container.api.ForgeIngressHeaders.INVOCATION_ID;
import static java.util.Collections.singletonMap;

@RestController
@RequestMapping("webtrigger")
public class WebTriggerEndpoint {

    private static final Logger log = LoggerFactory.getLogger(WebTriggerEndpoint.class);

    private final EgressClient egressClient;
    private final BookRepository bookRepository;

    public WebTriggerEndpoint(EgressClient egressClient, BookRepository bookRepository) {
        this.egressClient = egressClient;
        this.bookRepository = bookRepository;
    }

    @ResponseBody
    @PostMapping("/http")
    public Map<String, String> post(@RequestHeader(INVOCATION_ID) String invocationId) {

        // Fetch invocationContext
        final ResponseEntity<JsonNode> invocationContext = egressClient.getInvocationContext(invocationId);
        log.info("Invocation context: {}", invocationContext.getBody());

        // Make Jira Request
        log.info("Received Jira response: {}", egressClient.getCurrentUser(invocationId, AuthType.app));

        return singletonMap("message", "Hello Forge Container World");
    }

    @ResponseBody
    @PostMapping("/egress")
    public Map<String, String> egress(@RequestHeader(INVOCATION_ID) String invocationId) {

        // Make Egress Request
        final String egressUrl = "docs.googleapis.com/$discovery/rest?version=v1";
        final ResponseEntity<JsonNode> egressResponse = egressClient.sendEgressRequest(invocationId, HttpMethod.GET, egressUrl);
        log.info("Received egress response with status code: {}", egressResponse.getStatusCode());

        if (!egressResponse.getStatusCode().is2xxSuccessful()) {
            throw new ResponseStatusException(HttpStatusCode.valueOf(500),
                    "Egress request failed with status code: " + egressResponse.getStatusCode());
        }

        return singletonMap("message", "Hello Forge Container World");
    }

    @ResponseBody
    @PostMapping("/sql")
    public Map<String, String> sqlRequest(@RequestHeader(INVOCATION_ID) String invocationId) {
        final String bookTitle = "Lord of the Rings";
        final Optional<Book> bookByTitle = bookRepository.getBookByTitle(invocationId, bookTitle)
            .or(() -> {
                log.info("Book not found, creating new book");
                return bookRepository.createBook(invocationId, bookTitle, "J. R. R. Tolkien");
            });

        log.info("Fetched book by title: {}", bookByTitle);

        return singletonMap("fetchedBook", bookByTitle.get().id());
    }

    /**
     * 
     * Perform a series of KVS operations. The operations to perform are passed in via the webtrigger request body,
     * e.g. curl -X POST <webtrigger URL> -d '{"set": [..], "delete": [...], "check": [...]}'
     * 
     */
    @ResponseBody
    @PostMapping("/kvs-transaction")
    public Map<String, String> kvsTransaction(@RequestHeader(INVOCATION_ID) String invocationId, @RequestBody JsonNode body) {

        log.info("Running KVS transaction for invocationId={}, body={}", invocationId, body);

        // Extract transaction operations from webtrigger request body and transform into a KvsTransactionRequest object
        var setOperations = new ArrayList<EgressClient.SetTransactionSchema>();
        if (body.hasNonNull("set")) {
            body.get("set").forEach(setOperation -> 
                setOperations.add(new EgressClient.SetTransactionSchema(setOperation.get("key").asText(), setOperation.get("value").asText())
            ));
        }

        var deleteOperations = new ArrayList<EgressClient.BaseTransactionSchema>();
        if (body.hasNonNull("delete")) {
            body.get("delete").forEach(deleteOperation -> 
                deleteOperations.add(new EgressClient.BaseTransactionSchema(deleteOperation.get("key").asText())
            ));
        }

        var checkOperations = new ArrayList<EgressClient.BaseTransactionSchema>();
        if (body.hasNonNull("check")) {
            body.get("check").forEach(checkOperation -> 
                checkOperations.add(new EgressClient.BaseTransactionSchema(checkOperation.get("key").asText())
            ));
        }
       
        var request = new EgressClient.KvsTransactionRequest(setOperations, deleteOperations, checkOperations);
        ResponseEntity<JsonNode> kvsResponse = egressClient.executeKvsTransaction(invocationId, request);
        log.info("KVS result: {}", kvsResponse);

        return singletonMap("message", "KVS transaction performed successfully");
    }

    /**
     * Call the dynamic modules API. The method, alongside the key and body (depending on the API being called)
     * will need to be passed in via the webtrigger request body. See the following examples on how to call this webtrigger.
     * 1. Creating a dynamic module (POST):
     * curl -X POST <webtrigger URL> -d '{
     *   "method": "POST",
     *   "body": {
     *     "key": "test",
     *     "type": "trigger",
     *     "data": {
     *       "key": "test-trigger-key",
     *       "function": "handler",
     *       "events": [ "avi:jira:created:issue" ]
     *     }
     *   }
     * }'
     *
     * 2. Querying a dynamic module (GET). The queryParams field is optional:
     * curl -X GET <webtrigger URL> -d '{
     *   "method": "GET",
     *   "key": "test",
     * }'
     * 
     * curl -X GET <webtrigger URL> -d '{
     *   "method": "GET",
     *   "queryParams": "limit=10&nextPageToken=next-page-token"
     * }'
     * 
     * The other methods follow the same pattern.
     */
    @ResponseBody
    @PostMapping("/dynamic-modules")
    public Map<String, String> dynamicModules(@RequestHeader(INVOCATION_ID) String invocationId, @RequestBody JsonNode requestBody) {
        final String httpMethodString = requestBody.hasNonNull("method") ? requestBody.get("method").asText() : "UNKNOWN";
        final HttpMethod httpMethod = parseHttpMethod(httpMethodString);
        final String queryParams = requestBody.hasNonNull("queryParams") ? "?" + requestBody.get("queryParams").asText() : "";
        final String key = requestBody.hasNonNull("key") ? "/" + requestBody.get("key").asText(): "";
        final JsonNode body = requestBody.hasNonNull("body") ? requestBody.get("body") : null;

        log.info("Invoking dynamic modules API with invocationId = {}, method={}, key={}, body={}",
                invocationId, httpMethod, key, body);
        final ResponseEntity<JsonNode> dynamicModuleEgressResponse = egressClient.executeDynamicModuleRequest(
                invocationId, httpMethod, key, queryParams, body);
        log.info("Received dynamic module response: {}", dynamicModuleEgressResponse);

        return singletonMap("message",
                String.format("Dynamic modules request completed successfully with response code: %s", dynamicModuleEgressResponse.getStatusCode()));
    }

    private HttpMethod parseHttpMethod(final String method) {
        if (method == null || !method.matches("(?i)GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|TRACE")) {
            throw new IllegalStateException("Invalid HTTP method: " + method);
        }
        return HttpMethod.valueOf(method.toUpperCase());
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, String>> handleIllegalState(IllegalStateException ex) {
        log.error("Internal server error: {}", ex.getMessage());
        return ResponseEntity.internalServerError().body(singletonMap("error", ex.getMessage()));
    }
}
