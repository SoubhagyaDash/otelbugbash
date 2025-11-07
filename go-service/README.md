# Go Service

Go 1.21 HTTP service instrumented with OpenTelemetry SDK.

## Features

- OpenTelemetry tracing with OTLP HTTP/Protobuf exporter
- Manual instrumentation using Go SDK
- Context propagation
- Custom spans and events
- Health check endpoint

## Running Locally

### Prerequisites

- Go 1.21 or higher

### Steps

1. Install dependencies:
```bash
go mod download
```

2. Set environment variables:
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="localhost:4318"
export PORT="8080"
```

3. Run the application:
```bash
go run main.go
```

4. Test endpoints:
```bash
# Health check
curl http://localhost:8080/health

# Compute request
curl http://localhost:8080/api/compute

# Trigger error
curl http://localhost:8080/api/compute?error=true
```

## Docker Build

```bash
docker build -t go-service:latest .
docker run -p 8080:8080 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=host.docker.internal:4318 \
  go-service:latest
```

## Environment Variables

- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP endpoint (default: localhost:4318)
- `PORT`: HTTP server port (default: 8080)

## Endpoints

- `GET /health` - Health check
- `GET /api/compute` - Computation endpoint with simulated processing
- `GET /api/compute?error=true` - Trigger error for testing
- `GET /api/metrics` - Service metrics

## OpenTelemetry Implementation

This service demonstrates manual OpenTelemetry instrumentation:

- OTLP HTTP exporter with protobuf
- Trace context propagation
- Custom span creation
- Span events and attributes
- Error recording
