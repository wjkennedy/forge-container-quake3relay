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
 * Servlet filter that extracts the invocation attributes from the request header and sets it in the MDC (Mapped Diagnostic Context)
 * This ensures that the invocation attributes are available for logging purposes throughout the request processing lifecycle
 * and improves the traceability of logs related to specific invocations ingested into the Forge Developer Console.
 */
@Component
public class InvocationLoggingFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        try {
            final HttpServletRequest httpRequest = (HttpServletRequest) request;
            final String attributes = httpRequest.getHeader(ForgeIngressHeaders.INVOCATION_LOGGING_ATTRIBUTES);

            if (StringUtils.hasText(attributes)) {
                MDC.put(ForgeLogConstants.INVOCATION_ATTRIBUTES, attributes);
            }

            chain.doFilter(request, response);
        } finally {
            MDC.remove(ForgeLogConstants.INVOCATION_ATTRIBUTES);
        }
    }
} 