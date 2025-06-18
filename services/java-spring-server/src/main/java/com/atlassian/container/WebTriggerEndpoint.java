package com.atlassian.container;

import com.atlassian.container.db.Book;
import com.atlassian.container.db.BookRepository;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

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
        log.info("Received egress status code: {}", egressClient.getStatusCode(invocationId));

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
}
