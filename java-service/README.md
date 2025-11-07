# Java Service

Spring Boot 3.2 application **without manual instrumentation**. This service will be auto-instrumented using the OpenTelemetry Java agent.

## Features

- Spring Boot 3.2 with Java 17
- NO manual OpenTelemetry code
- Auto-instrumented via OpenTelemetry Java agent
- REST API endpoints
- Calls Go service downstream
- Health checks and metrics

## Running Locally

### Prerequisites

- Java 17 or higher
- Gradle

### Steps

1. Build the application:
```bash
./gradlew build
```

2. Download OpenTelemetry Java agent:
```bash
wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar
```

3. Run with auto-instrumentation:
```bash
java -javaagent:./opentelemetry-javaagent.jar \
  -Dotel.service.name=java-service \
  -Dotel.traces.exporter=otlp \
  -Dotel.exporter.otlp.protocol=http/protobuf \
  -Dotel.exporter.otlp.endpoint=http://localhost:4318 \
  -jar build/libs/java-service-1.0.0.jar
```

4. Test endpoints:
```bash
# Health check
curl http://localhost:8080/api/health

# Calculate (calls Go service)
curl http://localhost:8080/api/calculate

# Trigger error
curl http://localhost:8080/api/calculate?error=true
```

## Docker Build

The Dockerfile automatically includes the OpenTelemetry Java agent:

```bash
docker build -t java-service:latest .
docker run -p 8080:8080 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4318 \
  -e GO_SERVICE_URL=http://go-service:8080 \
  java-service:latest
```

## Environment Variables

- `GO_SERVICE_URL`: Go service URL (default: http://go-service:8080)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP endpoint (default: http://localhost:4318)
- `OTEL_SERVICE_NAME`: Service name for traces (default: java-service)

## Endpoints

- `GET /api/health` - Health check
- `GET /api/calculate` - Main calculation endpoint (calls Go service)
- `GET /api/calculate?error=true` - Trigger error for testing
- `GET /api/metrics` - Service metrics
- `GET /actuator/health` - Spring Actuator health

## Auto-Instrumentation

This service demonstrates OpenTelemetry auto-instrumentation:

- **No code changes required** for basic tracing
- Automatic span creation for HTTP requests
- Automatic context propagation
- Configurable via environment variables or system properties

The Java agent automatically instruments:
- Spring MVC controllers
- RestTemplate HTTP calls
- JDBC calls (if applicable)
- And many more frameworks
