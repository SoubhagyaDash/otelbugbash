# OpenTelemetry Configuration Guide

This document describes the OpenTelemetry configuration for all services in the bug bash environment.

## Overview

The .NET service uses **gRPC OTLP exporters** with separate endpoints for different telemetry signals, while Java and Go services use HTTP/Protobuf exporters.

## Configuration by Service

### .NET Service (VM)

**Protocol**: gRPC  
**Location**: Virtual Machine  
**Signals**: Traces, Metrics, Logs

#### Endpoints

| Signal | Port | Environment Variable | Default |
|--------|------|---------------------|---------|
| Traces & Logs | 4319 | `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | `http://localhost:4319` |
| Metrics | 4317 | `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | `http://localhost:4317` |

#### Implementation Details

```csharp
// Traces - gRPC on port 4319
.WithTracing(tracing => tracing
    .AddAspNetCoreInstrumentation()
    .AddHttpClientInstrumentation()
    .AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri("http://localhost:4319");
        options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
    }))

// Metrics - gRPC on port 4317
.WithMetrics(metrics => metrics
    .AddAspNetCoreInstrumentation()
    .AddHttpClientInstrumentation()
    .AddRuntimeInstrumentation()
    .AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri("http://localhost:4317");
        options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
    }))

// Logs - gRPC on port 4319 (same as traces)
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri("http://localhost:4319");
        options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
    });
});
```

#### Instrumentation

- **ASP.NET Core**: Automatic HTTP server instrumentation
- **HTTP Client**: Automatic outbound HTTP instrumentation
- **Runtime Metrics**: CLR metrics (GC, thread pool, etc.)
- **Custom Spans**: Manual ActivitySource for business logic
- **Logging**: Structured logging with OpenTelemetry integration

#### NuGet Packages

```xml
<PackageReference Include="OpenTelemetry" Version="1.9.0" />
<PackageReference Include="OpenTelemetry.Exporter.OpenTelemetryProtocol" Version="1.9.0" />
<PackageReference Include="OpenTelemetry.Extensions.Hosting" Version="1.9.0" />
<PackageReference Include="OpenTelemetry.Instrumentation.AspNetCore" Version="1.9.0" />
<PackageReference Include="OpenTelemetry.Instrumentation.Http" Version="1.9.0" />
<PackageReference Include="OpenTelemetry.Instrumentation.Runtime" Version="1.9.0" />
```

---

### Java Service (AKS)

**Protocol**: HTTP/Protobuf  
**Location**: Azure Kubernetes Service  
**Signals**: Traces (via auto-instrumentation)

#### Endpoints

| Signal | Port | Environment Variable | Default |
|--------|------|---------------------|---------|
| All Signals | 4318 | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` |

#### Implementation Details

Auto-instrumented using OpenTelemetry Java Agent:

```dockerfile
# Java agent downloaded at build time
RUN wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v1.32.0/opentelemetry-javaagent.jar

# Application runs with agent
ENTRYPOINT ["java", "-javaagent:/app/opentelemetry-javaagent.jar", "-jar", "/app/app.jar"]
```

#### Java Agent Configuration

Configured via environment variables:

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "java-service"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://localhost:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
```

#### Instrumentation

- **Spring MVC**: Automatic HTTP server instrumentation
- **RestTemplate**: Automatic HTTP client instrumentation
- **JDBC**: Database instrumentation (if database is added)
- **No code changes required**: Zero-touch instrumentation

---

### Go Service (AKS)

**Protocol**: HTTP/Protobuf  
**Location**: Azure Kubernetes Service  
**Signals**: Traces

#### Endpoints

| Signal | Port | Environment Variable | Default |
|--------|------|---------------------|---------|
| Traces | 4318 | `OTEL_EXPORTER_OTLP_ENDPOINT` | `localhost:4318` |

#### Implementation Details

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
    "go.opentelemetry.io/otel/sdk/trace"
)

// OTLP HTTP exporter
exporter, err := otlptracehttp.New(ctx,
    otlptracehttp.WithEndpoint(otlpEndpoint),
    otlptracehttp.WithInsecure(),
)

// Tracer provider
tp := trace.NewTracerProvider(
    trace.WithBatcher(exporter),
    trace.WithResource(resource),
)
otel.SetTracerProvider(tp)
```

#### Instrumentation

- **Manual SDK**: Explicit span creation and management
- **HTTP Server**: Custom middleware for request tracing
- **Context Propagation**: W3C Trace Context for distributed tracing

#### Go Modules

```go
require (
    go.opentelemetry.io/otel v1.21.0
    go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.21.0
    go.opentelemetry.io/otel/sdk v1.21.0
)
```

---

## Deployment Configuration

### Docker Compose (VM)

```yaml
services:
  dotnet-service:
    image: <acr-name>.azurecr.io/dotnet-service:latest
    environment:
      - OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://your-collector:4319
      - OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://your-collector:4317
      - JAVA_SERVICE_URL=http://java-service-ip:8080
    ports:
      - "5000:5000"
```

### Kubernetes (AKS)

**Java Service:**
```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://your-collector:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
```

**Go Service:**
```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "your-collector:4318"
```

---

## OpenTelemetry Collector Configuration

To receive telemetry from all services, configure your OpenTelemetry Collector with:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317  # Metrics from .NET
      grpc/traces:
        endpoint: 0.0.0.0:4319  # Traces/Logs from .NET
      http:
        endpoint: 0.0.0.0:4318  # Java & Go services

exporters:
  # Your backend exporters (e.g., Azure Monitor, Jaeger, Prometheus)
  azuremonitor:
    connection_string: "YOUR_CONNECTION_STRING"

service:
  pipelines:
    traces:
      receivers: [otlp, otlp/traces]
      exporters: [azuremonitor]
    metrics:
      receivers: [otlp]
      exporters: [azuremonitor]
    logs:
      receivers: [otlp/traces]
      exporters: [azuremonitor]
```

---

## Testing Configuration

### Test .NET Service Endpoints

```bash
# Set collector endpoints
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://your-collector:4319"
export OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="http://your-collector:4317"

# Run service
dotnet run
```

### Verify Telemetry

1. **Check traces**: Look for distributed trace starting from .NET → Java → Go
2. **Check metrics**: Verify runtime metrics (GC, requests, duration)
3. **Check logs**: Verify structured logs with trace correlation

### Load Testing

```bash
# Generate load to create telemetry
cd load-generator
go run main.go --url http://vm-ip:5000 --duration 5m --concurrency 10
```

---

## Port Reference

| Port | Protocol | Service | Signal Type | Format |
|------|----------|---------|-------------|--------|
| 4317 | gRPC | .NET Service | Metrics | OTLP/gRPC |
| 4318 | HTTP | Java Service, Go Service | Traces | OTLP/HTTP/Protobuf |
| 4319 | gRPC | .NET Service | Traces & Logs | OTLP/gRPC |

---

## Troubleshooting

### .NET Service Not Sending Telemetry

```bash
# Check environment variables
docker exec dotnet-service env | grep OTEL

# Verify collector is reachable
docker exec dotnet-service curl -v http://your-collector:4319

# Check logs
docker logs dotnet-service
```

### Java Service Auto-Instrumentation Issues

```bash
# Verify Java agent is loaded
kubectl logs -l app=java-service | grep "opentelemetry-javaagent"

# Check environment variables
kubectl exec -it <java-pod> -- env | grep OTEL
```

### Go Service Connection Issues

```bash
# Check endpoint configuration
kubectl logs -l app=go-service | grep "OTLP endpoint"

# Verify network connectivity
kubectl exec -it <go-pod> -- nc -zv your-collector 4318
```

---

## Migration Notes

### Previous Configuration (Before gRPC Update)

The .NET service previously used HTTP/Protobuf on port 4318:

```csharp
// OLD - HTTP/Protobuf
options.Endpoint = new Uri("http://localhost:4318");
options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.HttpProtobuf;
```

### Current Configuration (After gRPC Update)

The .NET service now uses gRPC with separate endpoints:

```csharp
// NEW - gRPC with separate endpoints
// Traces/Logs: port 4319
// Metrics: port 4317
options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
```

### Why the Change?

- **Better separation**: Different signals can be routed to different backends
- **gRPC performance**: Better throughput and lower latency for telemetry export
- **Production readiness**: Aligns with recommended production configurations
- **Flexibility**: Easier to scale and manage different signal types

---

## Additional Resources

- [OpenTelemetry .NET Documentation](https://opentelemetry.io/docs/instrumentation/net/)
- [OpenTelemetry Java Auto-Instrumentation](https://opentelemetry.io/docs/instrumentation/java/automatic/)
- [OpenTelemetry Go Documentation](https://opentelemetry.io/docs/instrumentation/go/)
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/)
