package com.atlassian.container.db;

import com.atlassian.container.EgressClient;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;

@Component
public class BookRepository {

    private static final Logger log = LoggerFactory.getLogger(BookRepository.class);

    private final EgressClient egressClient;
    private final ObjectMapper objectMapper;

    public BookRepository(EgressClient egressClient, ObjectMapper objectMapper) {
        this.egressClient = egressClient;
        this.objectMapper = objectMapper;
    }

    public Optional<Book> getBookByTitle(final String invocationId, final String title) {

        log.info("Fetching book by title: {}", title);

        final String booksByTitleQuery = """
                SELECT * FROM books WHERE title = ?;
                """;

        return Optional.ofNullable(egressClient.runSQLQuery(invocationId, booksByTitleQuery, List.of(title)))
                .map(ResponseEntity::getBody)
                .map(body -> body.get("rows"))
                .filter(rows -> !rows.isEmpty())
                .map(rows -> rows.get(0))
                .map(data -> objectMapper.convertValue(data, Book.class));
    }

    public Optional<Book> createBook(final String invocationId, String title, String author) {

        log.info("Creating book: {} {}", title, author);

        final String createBookSql = """
                INSERT INTO Books (title, author) VALUES (?, ?);
        """;

        return Optional.ofNullable(egressClient.runSQLQuery(invocationId, createBookSql, List.of(title, author)))
                .map(ResponseEntity::getBody)
                .map(body -> body.get("rows"))
                .filter(rows -> !rows.isEmpty())
                .map(rows -> rows.get(0))
                .map(data -> objectMapper.convertValue(data, Book.class));
    }
}
