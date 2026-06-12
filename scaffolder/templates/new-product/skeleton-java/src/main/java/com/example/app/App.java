package com.example.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Minimal Spring Boot service for app-${{ values.team }}-${{ values.product }}. The HTTP routes live in
 * {@link HealthController}. No cloud/AWS deps — a tenant's AWS access (if any) is granted out-of-band via EKS
 * Pod Identity to the named ServiceAccount. (The package stays com.example.app — Java packages can't contain
 * hyphens; rename it for your real app.)
 */
@SpringBootApplication
public class App {
    public static void main(String[] args) {
        SpringApplication.run(App.class, args);
    }
}
