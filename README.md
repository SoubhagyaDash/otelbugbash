# OpenTelemetry Bug Bash Environment

This repository contains a comprehensive multi-service application for bug bashing OpenTelemetry offerings in Azure.

## Architecture

```
Load Generator (VM) --> .NET App (VM) --> Java App (AKS) --> Go App (AKS)
```

### Components

1. **VM-based Services**:
   - .NET 8 Web API (instrumented with OpenTelemetry SDK - gRPC)
   - Load Generator (generates traffic and reports)

2. **AKS-based Services**:
   - Java Spring Boot API (auto-instrumented via Java agent)
   - Go Web API (instrumented with OpenTelemetry SDK - HTTP/Protobuf)

## Quick Start

### Prerequisites

**Required:**
- ✅ Azure subscription (Contributor access)
- ✅ Azure CLI installed and authenticated (`az login`)
- ✅ kubectl installed
- ✅ SSH client
- ✅ Git
- ✅ SSH key pair (for VM access)

**Not Required:**
- ❌ Docker (builds happen in Azure ACR)
- ❌ .NET, Java, or Go SDKs (not needed locally)

**📖 See [PREREQUISITES.md](./PREREQUISITES.md) for detailed setup instructions and environment validation.**

### Deployment

1. Clone this repository
2. Login to Azure:
   ```bash
   az login
   ```

3. Generate SSH key (if needed):
   ```bash
   ssh-keygen -t rsa -b 4048 -f ~/.ssh/otelbugbash_rsa
   ```

4. Deploy everything with one command:
   ```bash
   cd scripts
   ./deploy-all.sh otel-bugbash-rg eastus ~/.ssh/otelbugbash_rsa.pub http://your-collector:4319 http://your-collector:4317
   ```

This automatically:
- Creates Azure Container Registry
- Deploys VM and AKS infrastructure
- Builds and pushes all container images
- Deploys services from ACR to VM and AKS

## Detailed Instructions

See [BUGBASH_INSTRUCTIONS.md](./BUGBASH_INSTRUCTIONS.md) for complete setup and testing guide.

## Directory Structure

```
.
├── dotnet-service/        # .NET Web API with OTel SDK
├── java-service/          # Java Spring Boot API (uninstrumented)
├── go-service/            # Go Web API with OTel SDK
├── load-generator/        # Load testing tool
├── infrastructure/        # Bicep templates (includes ACR)
├── k8s/                   # Kubernetes manifests
└── scripts/               # Deployment and setup scripts
```

## Container Registry

All services are containerized and deployed from Azure Container Registry (ACR):

- **ACR is automatically created** during deployment
- **Images are automatically built** and pushed to ACR
- **VM and AKS** pull images from ACR
- **No local Docker build required** for deployment

Container images:
- `dotnet-service:latest`
- `java-service:latest`
- `go-service:latest`
- `load-generator:latest`

## OpenTelemetry Configuration

### .NET Service (VM)
- **OTLP Protocol**: gRPC
- **Traces/Logs Port**: 4319
- **Metrics Port**: 4317
- **Signals**: Traces, Metrics, Logs
- **Instrumentation**: Manual SDK

### Java Service (AKS)
- **OTLP Protocol**: HTTP/Protobuf
- **Port**: 4318
- **Signals**: Traces
- **Instrumentation**: Auto-instrumentation via Java agent

### Go Service (AKS)
- **OTLP Protocol**: HTTP/Protobuf
- **Port**: 4318
- **Signals**: Traces
- **Instrumentation**: Manual SDK

## Security

⚠️ **This repository is designed to be safely shared on GitHub.**

- ✅ No secrets are hardcoded
- ✅ All sensitive values use parameters or environment variables
- ✅ SSH keys and passwords are never committed
- ✅ `.gitignore` configured to block sensitive files

**Before committing changes:**
```bash
./scripts/check-for-secrets.sh
```

See [SECURITY.md](./SECURITY.md) for detailed security guidelines.

## License

MIT
