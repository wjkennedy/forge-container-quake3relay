package com.atlassian.container;

import com.atlassian.container.db.Book;
import com.atlassian.container.db.BookRepository;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.ExceptionHandler;

import java.util.Map;
import java.util.Optional;

import static com.atlassian.container.api.ForgeIngressHeaders.INVOCATION_ID;
import static java.util.Collections.singletonMap;

@RestController
public class WebTriggerEndpoint {

    private static final Logger log = LoggerFactory.getLogger(WebTriggerEndpoint.class);

    private final EgressClient egressClient;
    private final BookRepository bookRepository;

    public WebTriggerEndpoint(EgressClient egressClient, BookRepository bookRepository) {
        this.egressClient = egressClient;
        this.bookRepository = bookRepository;
    }

    @ResponseBody
    @PostMapping("/webtrigger")
    public Map<String, String> post(@RequestHeader(INVOCATION_ID) String invocationId) {

        //Fetch invocationContext
        final ResponseEntity<JsonNode> invocationContext = egressClient.getInvocationContext(invocationId);
        log.info("Invocation context: {}", invocationContext.getBody());

        //Make Egress Request
        final String egressUrl = "httpbin.org/get?key=value";
        final ResponseEntity<JsonNode> egressResponse = egressClient.sendEgressRequest(invocationId, HttpMethod.GET, egressUrl);
        log.info("Received egress response: {}", egressResponse);
        validateEgressResponse(egressResponse, "https://" + egressUrl);

        //Make Jira Request
        log.info("Received Jira response: {}", egressClient.getAppUserInfo(invocationId));

        //Make SQL Request
        final String bookTitle = "Lord of the Rings";
        final Optional<Book> bookByTitle = bookRepository.getBookByTitle(invocationId, bookTitle)
            .or(() -> {
                log.info("Book not found, creating new book");
                return bookRepository.createBook(invocationId, bookTitle, "J. R. R. Tolkien");
            });

        log.info("Fetched book by title: {}", bookByTitle);

        return singletonMap("message", "Hello Forge Container World");
    }

    private void validateEgressResponse(final ResponseEntity<JsonNode> response, final String expectedUrl) {
        final String requestedUrl = Optional.ofNullable(response.getBody())
                .map(body -> body.get("url"))
                .map(JsonNode::asText)
                .orElse(null);

        if (!expectedUrl.equals(requestedUrl)) {
            log.error("Egress response URL mismatch: expected '{}', got '{}'", expectedUrl, requestedUrl);
            throw new IllegalStateException("Egress response URL mismatch: expected '" + expectedUrl + "', got '" + requestedUrl + "'");
        }
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, String>> handleIllegalState(IllegalStateException ex) {
        log.error("Internal server error: {}", ex.getMessage());
        return ResponseEntity.internalServerError().body(singletonMap("error", ex.getMessage()));
    }
}
