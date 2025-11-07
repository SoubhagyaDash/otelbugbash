# .NET Service

ASP.NET Core 8.0 Web API instrumented with OpenTelemetry SDK.

## Features

- OpenTelemetry tracing, metrics, and logging with OTLP gRPC exporter
- Automatic ASP.NET Core instrumentation
- Automatic HTTP client instrumentation
- Runtime metrics instrumentation
- Custom spans and events
- Health check endpoint
- Calls Java service downstream

## Running Locally

### Prerequisites

- .NET 8.0 SDK

### Steps

1. Set environment variables:
```bash
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://localhost:4319"
export OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="http://localhost:4317"
export JAVA_SERVICE_URL="http://localhost:8080"
```

2. Run the application:
```bash
dotnet run
```

3. Test endpoints:
```bash
# Health check
curl http://localhost:5000/health

# Process request (calls Java service)
curl http://localhost:5000/api/process

# Trigger error
curl http://localhost:5000/api/process?error=true
```

## Docker Build

```bash
docker build -t dotnet-service:latest .
docker run -p 5000:5000 \
  -e OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://host.docker.internal:4319 \
  -e OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://host.docker.internal:4317 \
  -e JAVA_SERVICE_URL=http://java-service:8080 \
  dotnet-service:latest
```

## Environment Variables

- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`: OTLP endpoint for traces and logs (default: http://localhost:4319) - **gRPC**
- `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`: OTLP endpoint for metrics (default: http://localhost:4317) - **gRPC**
- `JAVA_SERVICE_URL`: Java service URL (default: http://java-service:8080)
- `ASPNETCORE_URLS`: Listen address (default: http://+:5000)

## Endpoints

- `GET /health` - Health check
- `GET /api/process` - Main processing endpoint (calls Java service)
- `GET /api/process?error=true` - Trigger error for testing
- `GET /api/metrics` - Service metrics
