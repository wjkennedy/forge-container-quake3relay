package com.atlassian.container;

import com.atlassian.container.models.AtlassianDocumentFormat;
import com.atlassian.container.models.ProductEventTrigger;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static com.atlassian.container.api.ForgeIngressHeaders.INVOCATION_ID;

@RestController
public class ProductEventTriggerEndpoint {

    private static final Logger log = LoggerFactory.getLogger(ProductEventTriggerEndpoint.class);
    private final EgressClient egressClient;

    public ProductEventTriggerEndpoint(EgressClient egressClient) {
        this.egressClient = egressClient;
    }

    @PostMapping("/product-event-trigger")
    @ResponseStatus(HttpStatus.OK)
    public void post(@RequestHeader(INVOCATION_ID) String invocationId, @RequestBody ProductEventTrigger event) {
        log.info("Received invocationId: {}", invocationId);
        log.info("Received body: {}", event);

        String eventType = event.eventType();

        log.info("Event Type: {}", eventType);

        if (eventType.equals("avi:jira:updated:issue")) {
            handleJiraUpdatedIssue(invocationId, event);
        }
    }

    private void handleJiraUpdatedIssue(String invocationId, ProductEventTrigger event) {
        log.info("Processing event for jira issue updated");
        String issueKey = event.issue().key();

        List<ProductEventTrigger.Item> changedItems = event.changelog().items();

        Optional<ProductEventTrigger.Item> firstDescriptionUpdate = changedItems.stream()
                .filter(item -> "description".equals(item.getField()))
                .findFirst();

        if (firstDescriptionUpdate.isPresent()) {
            String newDescription = firstDescriptionUpdate.get().getToString();
            log.info("Found an update to the 'description' field in the changelog: {}", newDescription);

            log.info("Commenting on issue key: {}", issueKey);

            AtlassianDocumentFormat document =
                    new AtlassianDocumentFormat(List.of(
                        new AtlassianDocumentFormat.Content(List.of(
                                new AtlassianDocumentFormat.TextContent(newDescription))
                            )
                    )
            );

            ObjectMapper mapper = new ObjectMapper();
            JsonNode commentToSend = mapper.valueToTree(Map.of("body", document));
            log.info("Sending comment: {}", commentToSend);

            ResponseEntity<JsonNode> commentOnIssueResponse = egressClient.commentOnIssue(invocationId, issueKey, commentToSend);
            log.info("Received jira response: {}", commentOnIssueResponse);
        } else {
            log.info("No updates to the 'description' field found in the changelog - doing nothing");
        }
    }
}
