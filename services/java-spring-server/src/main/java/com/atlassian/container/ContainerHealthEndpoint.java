package com.atlassian.container;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/health")
public class ContainerHealthEndpoint {

  private static final Logger log = LoggerFactory.getLogger(ContainerHealthEndpoint.class);

  @GetMapping
  @ResponseStatus(HttpStatus.OK)
  public String get() {
    return "OK";
  }
}
