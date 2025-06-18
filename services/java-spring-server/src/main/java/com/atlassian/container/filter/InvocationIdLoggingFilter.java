package com.atlassian.container.filter;

import com.atlassian.container.api.ForgeIngressHeaders;
import com.atlassian.container.api.ForgeLogConstants;
import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.io.IOException;

/**
 * Servlet filter that extracts the invocation ID from the request header and sets it in the MDC (Mapped Diagnostic Context)
 * This ensures that the invocation ID is available for logging purposes throughout the request processing lifecycle
 * and improves the traceability of logs related to specific invocations ingested into the Forge Developer Console.
 */
@Component
public class InvocationIdLoggingFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        try {
            final HttpServletRequest httpRequest = (HttpServletRequest) request;
            final String invocationId = httpRequest.getHeader(ForgeIngressHeaders.INVOCATION_ID);

            if (StringUtils.hasText(invocationId)) {
                MDC.put(ForgeLogConstants.INVOCATION_ID, invocationId);
            }

            chain.doFilter(request, response);
        } finally {
            MDC.remove(ForgeLogConstants.INVOCATION_ID);
        }
    }
} 