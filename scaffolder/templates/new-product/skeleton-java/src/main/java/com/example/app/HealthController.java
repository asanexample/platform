package com.example.app;

import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

    private static final String APP = "app-${{ values.team }}-${{ values.product }}";

    @GetMapping("/healthz")
    public Map<String, String> healthz() {
        return Map.of("status", "ok");
    }

    @GetMapping("/")
    public Map<String, String> root(HttpServletRequest request) {
        Map<String, String> body = new LinkedHashMap<>();
        body.put("app", APP);
        body.put("version", env("VERSION", "dev"));
        body.put("namespace", env("NAMESPACE", "unknown"));
        body.put("hostname", request.getHeader("Host") == null ? "" : request.getHeader("Host"));
        body.put("timestamp", Instant.now().toString());
        return body;
    }

    private static String env(String key, String def) {
        String v = System.getenv(key);
        return (v == null || v.isEmpty()) ? def : v;
    }
}
