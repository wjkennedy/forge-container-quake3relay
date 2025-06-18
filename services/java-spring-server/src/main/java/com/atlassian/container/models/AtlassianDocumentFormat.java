package com.atlassian.container.models;

import java.util.List;

public record AtlassianDocumentFormat(String type, int version, List<Content> content) {
    public AtlassianDocumentFormat(List<Content> content) {
        this("doc", 1, content);
    }

    public record Content(String type, List<TextContent> content) {
        public Content(List<TextContent> content) {
            this("paragraph", content);
        }
    }

    public record TextContent(String type, String text) {
        public TextContent(String text) {
            this("text", text);
        }
    }
}
