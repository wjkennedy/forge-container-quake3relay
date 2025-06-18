package com.atlassian.container.exceptions;

public class EgressRequestException extends RuntimeException {
    public EgressRequestException(String message) {
        super(message);
    }
}
