package com.atlassian.container.models;

import java.util.List;

public record ProductEventTrigger(String eventType, Issue issue, Changelog changelog) {
    public record Issue(String key) {}
    public record Changelog(List<Item> items) {}

    // cannot make this a record as 'toString' is a reserved keyword
    public static class Item {
        private String field;
        private String toString;

        public String getField() { return field; }
        public String getToString() { return toString; }
    }
}
