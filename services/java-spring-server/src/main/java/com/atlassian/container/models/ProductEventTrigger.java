package com.atlassian.container.models;

import java.util.List;

public record ProductEventTrigger(String eventType, Issue issue, Changelog changelog) {
    public record Issue(String key, Fields fields) {
        public record Fields(User assignee) {}
    }
    public record Changelog(List<Item> items) {}
    public record User(String accountId) {}

    // cannot make this a record as 'toString' is a reserved keyword
    public static class Item {
        private String field;
        private String toString;

        public String getField() { return field; }
        public String getToString() { return toString; }
    }
}
