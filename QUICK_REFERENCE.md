# Quick Reference: OpenTelemetry Endpoints

## .NET Service (VM) - gRPC

```bash
# Environment Variables
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4319
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://localhost:4317
```

**Signals Exported:**
- ✅ Traces (gRPC, port 4319)
- ✅ Metrics (gRPC, port 4317)
- ✅ Logs (gRPC, port 4319)

**Instrumentation:** Manual SDK

---

## Java Service (AKS) - HTTP/Protobuf

```bash
# Environment Variables
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

**Signals Exported:**
- ✅ Traces (HTTP, port 4318)

**Instrumentation:** Auto-instrumentation (Java Agent)

---

## Go Service (AKS) - HTTP/Protobuf

```bash
# Environment Variables
OTEL_EXPORTER_OTLP_ENDPOINT=localhost:4318
```

**Signals Exported:**
- ✅ Traces (HTTP, port 4318)

**Instrumentation:** Manual SDK

---

## Deployment Command

```bash
./scripts/deploy-all.sh \
  otel-bugbash-rg \
  eastus \
  ~/.ssh/otelbugbash_rsa.pub \
  http://collector:4319 \
  http://collector:4317
```

---

## Collector Configuration

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317  # .NET metrics
      grpc/traces:
        endpoint: 0.0.0.0:4319  # .NET traces/logs
      http:
        endpoint: 0.0.0.0:4318  # Java & Go
```

---

## Port Summary

| Port | Protocol | Service | Signals |
|------|----------|---------|---------|
| 4317 | gRPC | .NET | Metrics |
| 4318 | HTTP | Java, Go | Traces |
| 4319 | gRPC | .NET | Traces, Logs |
