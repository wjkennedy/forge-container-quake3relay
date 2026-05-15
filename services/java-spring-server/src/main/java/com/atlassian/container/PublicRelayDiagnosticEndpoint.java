package com.atlassian.container;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.WebSocket;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.TimeUnit;

@RestController
@RequestMapping("/diag")
public class PublicRelayDiagnosticEndpoint {

    private static final Logger log = LoggerFactory.getLogger(PublicRelayDiagnosticEndpoint.class);
    private static final int DEFAULT_TIMEOUT_MS = 10000;
    private static final int BODY_SNIPPET_LIMIT = 400;

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofMillis(DEFAULT_TIMEOUT_MS))
            .build();

    @GetMapping("/public-relay")
    public ObjectNode get(
            @RequestParam(name = "healthUrl", required = false) String healthUrl,
            @RequestParam(name = "websocketUrl", required = false) String websocketUrl,
            @RequestParam(name = "timeoutMs", required = false) Integer timeoutMs
    ) {
        final int effectiveTimeoutMs = timeoutMs != null && timeoutMs > 0 ? timeoutMs : DEFAULT_TIMEOUT_MS;
        final String resolvedHealthUrl = isBlank(healthUrl)
                ? System.getenv().getOrDefault("PUBLIC_RELAY_HEALTH_URL", "https://q3a.a9group.net/healthz")
                : healthUrl;
        final String resolvedWebsocketUrl = isBlank(websocketUrl)
                ? System.getenv().getOrDefault("PUBLIC_RELAY_WEBSOCKET_URL", "wss://q3a.a9group.net")
                : websocketUrl;

        log.info("Running public relay diagnostic: healthUrl={}, websocketUrl={}, timeoutMs={}",
                resolvedHealthUrl, resolvedWebsocketUrl, effectiveTimeoutMs);

        final ObjectNode response = objectMapper.createObjectNode();
        response.put("timestamp", Instant.now().toString());
        response.put("healthUrl", resolvedHealthUrl);
        response.put("websocketUrl", resolvedWebsocketUrl);
        response.put("timeoutMs", effectiveTimeoutMs);

        final ObjectNode httpsResult = probeHealth(resolvedHealthUrl, effectiveTimeoutMs);
        final ObjectNode websocketResult = probeWebSocket(resolvedWebsocketUrl, effectiveTimeoutMs);

        response.set("https", httpsResult);
        response.set("websocket", websocketResult);
        response.put("ok", httpsResult.path("ok").asBoolean(false) && websocketResult.path("ok").asBoolean(false));
        return response;
    }

    private ObjectNode probeHealth(String url, int timeoutMs) {
        final ObjectNode result = objectMapper.createObjectNode();
        final long startedAt = System.nanoTime();

        try {
            final HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofMillis(timeoutMs))
                    .GET()
                    .build();

            final HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            final long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);
            final String body = response.body() == null ? "" : response.body();

            result.put("ok", response.statusCode() >= 200 && response.statusCode() < 300);
            result.put("statusCode", response.statusCode());
            result.put("latencyMs", elapsedMs);
            result.put("bodySnippet", truncate(body, BODY_SNIPPET_LIMIT));
        } catch (Exception exception) {
            final long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);
            result.put("ok", false);
            result.put("latencyMs", elapsedMs);
            result.put("error", rootMessage(exception));
            log.warn("Public relay HTTPS probe failed for {}: {}", url, exception.toString());
        }

        return result;
    }

    private ObjectNode probeWebSocket(String url, int timeoutMs) {
        final ObjectNode result = objectMapper.createObjectNode();
        final long startedAt = System.nanoTime();
        final CompletableFuture<String> statusFuture = new CompletableFuture<>();

        try {
            final WebSocket.Listener listener = new WebSocket.Listener() {
                @Override
                public void onOpen(WebSocket webSocket) {
                    statusFuture.complete("opened");
                    webSocket.sendClose(WebSocket.NORMAL_CLOSURE, "diagnostic");
                    WebSocket.Listener.super.onOpen(webSocket);
                }

                @Override
                public void onError(WebSocket webSocket, Throwable error) {
                    statusFuture.completeExceptionally(error);
                }

                @Override
                public CompletionStage<?> onClose(WebSocket webSocket, int statusCode, String reason) {
                    statusFuture.complete("closed:" + statusCode);
                    return WebSocket.Listener.super.onClose(webSocket, statusCode, reason);
                }
            };

            httpClient.newWebSocketBuilder()
                    .buildAsync(URI.create(url), listener)
                    .orTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                    .join();

            final String handshakeState = statusFuture.orTimeout(timeoutMs, TimeUnit.MILLISECONDS).join();
            final long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);

            result.put("ok", handshakeState.startsWith("opened") || handshakeState.startsWith("closed:"));
            result.put("latencyMs", elapsedMs);
            result.put("state", handshakeState);
        } catch (Exception exception) {
            final long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);
            result.put("ok", false);
            result.put("latencyMs", elapsedMs);
            result.put("error", rootMessage(exception));
            log.warn("Public relay WebSocket probe failed for {}: {}", url, exception.toString());
        }

        return result;
    }

    private static String truncate(String value, int maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    private static String rootMessage(Throwable throwable) {
        Throwable current = throwable;
        while (current.getCause() != null) {
            current = current.getCause();
        }

        final String message = current.getMessage();
        return message == null || message.isBlank() ? current.toString() : message;
    }
}
