# Multi-stage: build the fat jar with Maven (JDK21), run on distroless/java21 (no shell, non-root uid 65532).
# The jar is architecture-agnostic; multi-arch comes from the distroless runtime base (buildx pulls per-arch).
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /app
# Resolve dependencies first so the (large) dependency layer caches across source-only changes.
COPY pom.xml ./
RUN mvn -B -q -DskipTests dependency:go-offline

COPY src/ src/
RUN mvn -B -q -Dmaven.test.skip=true package

FROM gcr.io/distroless/java21-debian12:nonroot

WORKDIR /app
# finalName=app → target/app.jar (the Spring Boot repackaged executable jar). The distroless/java entrypoint
# is `java -jar`, so CMD is just the jar.
COPY --from=build /app/target/app.jar app.jar

EXPOSE 8080

# Run as the distroless non-root user (uid 65532) explicitly — satisfies the image-runs-as-root scanners.
USER 65532:65532

CMD ["app.jar"]
