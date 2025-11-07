# .NET Service OTLP Configuration Update

## Summary

Updated the .NET service to use **gRPC OTLP exporters** with separate endpoints for different telemetry signals.

## Changes Made

### 1. Program.cs - OpenTelemetry Configuration

**Before:**
- Single OTLP endpoint for traces only
- HTTP/Protobuf protocol on port 4318
- Only tracing instrumentation

**After:**
- Separate endpoints for traces/logs (4319) and metrics (4317)
- gRPC protocol for all signals
- Full instrumentation: traces, metrics, and logs

**Key Changes:**
```csharp
// Added imports
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;

// Added metrics pipeline
.WithMetrics(metrics => metrics
    .AddAspNetCoreInstrumentation()
    .AddHttpClientInstrumentation()
    .AddRuntimeInstrumentation()
    .AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri(otlpMetricsEndpoint);
        options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
    }))

// Added logging pipeline
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.IncludeFormattedMessage = true;
    logging.IncludeScopes = true;
    logging.AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri(otlpTracesLogsEndpoint);
        options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
    });
});
```

### 2. dotnet-service.csproj - NuGet Packages

**Added:**
- `OpenTelemetry.Instrumentation.Runtime` version 1.9.0 (for runtime metrics)

### 3. appsettings.json - Configuration

**Before:**
```json
"OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318"
```

**After:**
```json
"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT": "http://localhost:4319",
"OTEL_EXPORTER_OTLP_METRICS_ENDPOINT": "http://localhost:4317"
```

### 4. README.md - Documentation

**Updated:**
- Features section to mention gRPC and all three signals
- Environment variables section with new endpoint names
- Docker examples with new environment variables

### 5. Deployment Scripts

**vm-setup.sh:**
- Updated to accept two OTLP endpoints (traces and metrics)
- Changed from 3 parameters to 5 parameters
- Updated docker-compose.yml generation

**deploy-all.sh:**
- Updated to accept two OTLP endpoints
- Changed parameter passing to vm-setup.sh
- Updated console output messages

**scripts/README.md:**
- Updated deployment examples
- Updated parameter documentation

### 6. Infrastructure Files

**main.bicep:**
- Changed `otelEndpoint` parameter to `otelTracesEndpoint` and `otelMetricsEndpoint`
- Updated parameter descriptions

**main.parameters.json:**
- Split `otelEndpoint` into two parameters
- Updated default values to new ports

### 7. Documentation

**Created OTEL_CONFIGURATION.md:**
- Comprehensive guide to OpenTelemetry configuration
- Per-service configuration details
- Port reference table
- Troubleshooting guide
- Migration notes

**Updated README.md:**
- Updated deployment command examples
- Added detailed OpenTelemetry configuration section
- Updated .NET service description to mention gRPC

## Environment Variables

### New Environment Variables

| Variable | Purpose | Default | Protocol |
|----------|---------|---------|----------|
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Traces and logs endpoint | `http://localhost:4319` | gRPC |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Metrics endpoint | `http://localhost:4317` | gRPC |

### Removed Environment Variables

| Variable | Replaced By |
|----------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Split into traces and metrics endpoints |

## Port Configuration

| Port | Protocol | Signal Type | Usage |
|------|----------|-------------|-------|
| 4317 | gRPC | Metrics | Standard OTLP gRPC metrics port |
| 4318 | HTTP | All (Java/Go) | Standard OTLP HTTP port |
| 4319 | gRPC | Traces & Logs | Custom port for .NET traces/logs |

## Telemetry Signals

The .NET service now exports:

1. **Traces** (gRPC, port 4319)
   - HTTP server spans (ASP.NET Core)
   - HTTP client spans (outbound requests)
   - Custom application spans

2. **Metrics** (gRPC, port 4317)
   - HTTP server metrics (requests, duration)
   - HTTP client metrics (outbound requests)
   - Runtime metrics (GC, thread pool, exceptions)

3. **Logs** (gRPC, port 4319)
   - Structured application logs
   - Correlated with traces (trace ID, span ID)
   - Log levels and scopes

## Testing the Changes

### Local Testing

```bash
# Set environment variables
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://localhost:4319"
export OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="http://localhost:4317"
export JAVA_SERVICE_URL="http://localhost:8080"

# Run the service
cd dotnet-service
dotnet run

# Test endpoints
curl http://localhost:5000/health
curl http://localhost:5000/api/process
```

### Docker Testing

```bash
# Build image
docker build -t dotnet-service:latest .

# Run container
docker run -p 5000:5000 \
  -e OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://host.docker.internal:4319 \
  -e OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://host.docker.internal:4317 \
  -e JAVA_SERVICE_URL=http://java-service:8080 \
  dotnet-service:latest
```

### Deployment Testing

```bash
# Deploy with new configuration
cd scripts
./deploy-all.sh otel-bugbash-rg eastus ~/.ssh/key.pub \
  http://collector:4319 \
  http://collector:4317
```

## Collector Configuration

Your OpenTelemetry Collector should be configured to receive on both ports:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317  # Metrics
      grpc/traces:
        endpoint: 0.0.0.0:4319  # Traces & Logs
      http:
        endpoint: 0.0.0.0:4318  # Java & Go services

service:
  pipelines:
    traces:
      receivers: [otlp/traces]
      exporters: [your-exporter]
    metrics:
      receivers: [otlp]
      exporters: [your-exporter]
    logs:
      receivers: [otlp/traces]
      exporters: [your-exporter]
```

## Benefits

1. **Signal Separation**: Different signals can be routed independently
2. **Better Performance**: gRPC is more efficient than HTTP/Protobuf
3. **Production Ready**: Aligns with production best practices
4. **Complete Observability**: All three signals (traces, metrics, logs)
5. **Flexibility**: Easier to scale and manage different backends

## Backward Compatibility

⚠️ **Breaking Change**: This is a breaking change. Services using the old configuration will need to:

1. Update environment variables from `OTEL_EXPORTER_OTLP_ENDPOINT` to separate endpoints
2. Configure collector to accept gRPC on ports 4317 and 4319
3. Rebuild and redeploy the .NET service

## Files Modified

```
dotnet-service/
├── Program.cs                    # OpenTelemetry configuration
├── dotnet-service.csproj          # NuGet packages
├── appsettings.json              # Default configuration
└── README.md                      # Documentation

scripts/
├── deploy-all.sh                 # Deployment automation
├── vm-setup.sh                   # VM setup script
└── README.md                      # Scripts documentation

infrastructure/
├── main.bicep                    # Infrastructure parameters
└── main.parameters.json          # Default parameter values

Documentation/
├── README.md                     # Main documentation
├── OTEL_CONFIGURATION.md         # New: Detailed OTel config guide
└── (other docs updated)
```

## Verification Checklist

- [x] Program.cs updated with gRPC exporters
- [x] Separate endpoints for traces/logs and metrics
- [x] NuGet packages updated (Runtime instrumentation)
- [x] appsettings.json updated
- [x] README.md updated
- [x] deployment scripts updated
- [x] Infrastructure files updated
- [x] Documentation created (OTEL_CONFIGURATION.md)
- [x] All references to old port 4318 removed from .NET service

## Next Steps

1. **Test locally**: Run the .NET service locally with a collector
2. **Deploy to Azure**: Use updated deployment scripts
3. **Verify telemetry**: Confirm all three signals are being received
4. **Monitor performance**: Check gRPC performance vs HTTP/Protobuf
5. **Update collector**: Ensure collector is configured for new ports
