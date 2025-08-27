package com.atlassian.container;

import com.atlassian.container.api.ForgeEgressHeaders;
import com.atlassian.container.exceptions.EgressRequestException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.lang.Nullable;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.net.URI;
import java.util.List;
import java.util.Optional;

@Component
public class EgressClient {

  public enum AuthType {
    app,
    user
  }

  private static String getAuthHeader(final String invocationId, final AuthType authType, @Nullable final String accountId) {
    var authHeader = String.format("Forge id=%s", invocationId);
    if (authType != null) {
      authHeader += String.format(",as=%s", authType);
    }
    if (accountId != null) {
      authHeader += String.format(",accountId=%s", accountId);
    }

    return authHeader;
  }

  private final RestClient restClient;
  private final ObjectMapper objectMapper;

  @Value("${egress.proxy.url}")
  private String egressProxyUrl;

  public EgressClient(final RestClient.Builder restClientBuilder) {
    this.objectMapper = new ObjectMapper();
    this.restClient = restClientBuilder.build();
  }

  public ResponseEntity<JsonNode> getInvocationContext(final String invocationId) {
    var uri = URI.create(egressProxyUrl + "/invocation/context");
    return sendRequest("Context request", invocationId, HttpMethod.GET, uri, null, null);
  }

  public ResponseEntity<JsonNode> sendRequest(
          final String requestType,
          final String invocationId,
          final HttpMethod httpMethod,
          final URI uri,
          final AuthType authType,
          @Nullable final String accountId) {
    return sendRequestWithBody(requestType, invocationId, httpMethod, uri, null, authType, null);
  }

  public ResponseEntity<JsonNode> sendRequestWithBody(
          final String requestType,
          final String invocationId,
          final HttpMethod httpMethod,
          final URI uri,
          final Object body,
          final AuthType authType,
          @Nullable final String accountId
          ) {

    var request = restClient.method(httpMethod)
            .uri(uri)
            .header(ForgeEgressHeaders.FORGE_AUTHORIZATION, getAuthHeader(invocationId, authType, accountId));

    Optional.ofNullable(body)
            .ifPresent(request::body);

    return request.retrieve()
            .onStatus(HttpStatusCode::isError,
            (req, response) -> {
              throw new EgressRequestException(requestType + " failed with status " + response.getStatusCode() + ": " + response.getBody());
            }).toEntity(JsonNode.class);
  }

  public ResponseEntity<JsonNode> sendEgressRequest(
          final String invocationId,
          final HttpMethod httpMethod,
          final String apiPath) {

    var uri = URI.create(egressProxyUrl + "/proxy/" + apiPath);
    return sendRequest("Egress request", invocationId, httpMethod, uri, null, null);
  }

  public ResponseEntity<JsonNode> getCurrentUser(final String invocationId, AuthType authType) {
    return sendJiraRequest(invocationId, authType, HttpMethod.GET, "rest/api/3/myself", null, null);
  }

  public ResponseEntity<JsonNode> commentOnIssue(final String invocationId, String issueKey, Object body, @Nullable final String accountId) {
    String path = "/rest/api/3/issue/" + issueKey + "/comment";

    AuthType authType = AuthType.app;
    if (accountId != null) {
      authType = AuthType.user;
    }
    return sendJiraRequest(invocationId, authType, HttpMethod.POST, path, body, accountId);
  }

  public ResponseEntity<JsonNode> sendJiraRequest(
          final String invocationId,
          final AuthType authType,
          final HttpMethod httpMethod,
          final String apiPath,
          @Nullable final Object body,
          @Nullable final String accountId) {

    var uri = URI.create(egressProxyUrl + "/jira/" + apiPath);
    return Optional.ofNullable(body)
            .map(bodyJson -> sendRequestWithBody("Jira request", invocationId, httpMethod, uri, bodyJson, authType, accountId))
            .orElseGet(() -> sendRequest("Jira request", invocationId, httpMethod, uri, authType, accountId));
  }

  public ResponseEntity<JsonNode> publishRealtimeMessage(final String invocationId, final String channelName, final String payload) {
    var uri = URI.create(egressProxyUrl + "/forge/realtime/publish");

    final ObjectNode realtimeEvent = objectMapper.createObjectNode()
            .put("name", channelName)
            .put("payload", payload);

    return sendRequestWithBody("Publish realtime message", invocationId, HttpMethod.POST, uri, realtimeEvent, AuthType.app, null);
  }

  public ResponseEntity<JsonNode> runSQLQuery(final String invocationId, final String query,
          final List<Object> params) {

    final ObjectNode queryExecutionRequest = objectMapper.createObjectNode()
            .put("query", query)
            .put("method", "all")
            .set("params", objectMapper.valueToTree(params));

    var uri = URI.create(egressProxyUrl + "/forge/storage/sql/v1/execute");
    return sendRequestWithBody("SQL Execute", invocationId, HttpMethod.POST, uri, queryExecutionRequest, AuthType.app, null);
  }

  public ResponseEntity<JsonNode> setValueToKvs(final String invocationId, final String key, final String value) {

    final ObjectNode objectNodeSet = objectMapper.createObjectNode()
            .put("key", key)
            .put("value", value);

    var uri = URI.create(egressProxyUrl + "/forge/storage/kvs/v1/set");
    return sendRequestWithBody("Set KVS request", invocationId, HttpMethod.POST, uri, objectNodeSet, null, null);
  }

  public ResponseEntity<JsonNode> getValueFromKvs(final String invocationId, final String key) {

    final ObjectNode objectNodeGet = objectMapper.createObjectNode()
                    .put("key", key);

    var uri = URI.create(egressProxyUrl + "/forge/storage/kvs/v1/get");
    return sendRequestWithBody("Get KVS request", invocationId, HttpMethod.POST, uri, objectNodeGet, null, null);
  }

  /**
   * A Forge KvsTransactionRequest is a JSON object with the following structure:
   * {
   *   "set": [
   *      {
   *        "key": "<string>",
   *        "value": "<string>",
   *      }
   *    ],
   *   "delete": [
   *      {
   *        "key": "<string>",
   *      }
   *    ],
   *   "check": [
   *      {
   *        "key": "<string>",
   *      }
   *    ]
   * 
   * Reference: https://developer.atlassian.com/platform/forge/rest/api-group-transaction/#api-v1-transaction-post-request 
   */
  public record SetTransactionSchema(String key, String value) {}
  public record BaseTransactionSchema(String key) {}
  public record KvsTransactionRequest(List<SetTransactionSchema> set, List<BaseTransactionSchema> delete, List<BaseTransactionSchema> check) {}

  public ResponseEntity<JsonNode> executeKvsTransaction(final String invocationId, final KvsTransactionRequest data) {

    final ObjectNode transactionRequest = objectMapper.createObjectNode();

    var setArray = transactionRequest.putArray("set");
    data.set.forEach(setOperation -> setArray.add(objectMapper.valueToTree(setOperation)));

    var deleteArray = transactionRequest.putArray("delete");
    data.delete.forEach(deleteOperation -> deleteArray.add(objectMapper.valueToTree(deleteOperation)));

    var checkArray = transactionRequest.putArray("check");
    data.check.forEach(checkOperation -> checkArray.add(objectMapper.valueToTree(checkOperation)));

    var uri = URI.create(egressProxyUrl + "/forge/storage/kvs/v1/transaction");
    return sendRequestWithBody("Execute KVS transaction", invocationId, HttpMethod.POST, uri, transactionRequest, null, null);
  }

  /**
   * A Forge AsyncEvent is a JSON object with the following structure:
   * {
   *   "body": {
   *     "payload": {
   *       "key": "value"
   *     }
   *   }
   */
  public record AsyncEvent(Body body) {
    public record Body(JsonNode payload) {}
  }

  public ResponseEntity<JsonNode> queueAsyncEvent(final String invocationId, final String queueName, final List<AsyncEvent> events) {

    final ObjectNode eventRequest = objectMapper.createObjectNode()
            .put("queueName", queueName);

    var eventsArray = eventRequest.putArray("events");
    events.forEach(event -> eventsArray.add(objectMapper.valueToTree(event)));

    var uri = URI.create(egressProxyUrl + "/atlassian/forge/events/v1/async-events");
    return sendRequestWithBody("Queue Async Event", invocationId, HttpMethod.POST, uri, eventRequest, AuthType.app, null);
  }
}
