package com.atlassian.container;

import com.atlassian.container.exceptions.EgressRequestException;
import com.atlassian.container.exceptions.KvsResponseException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalControllerAdvice {

    private static final Logger log = LoggerFactory.getLogger(GlobalControllerAdvice.class);

    @ExceptionHandler({
            EgressRequestException.class,
    })
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public void handleBadRequest(Exception ex) {
        log.debug("Bad request", ex);
    }

    @ExceptionHandler({
            KvsResponseException.class
    })
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public void handleInternalError(Exception ex) {
        log.debug("Internal error", ex);
    }
}
