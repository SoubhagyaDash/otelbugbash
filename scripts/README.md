# Deployment Scripts

Scripts for deploying and managing the OpenTelemetry bug bash environment.

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `deploy-all.sh` | Complete end-to-end deployment |
| `deploy-to-aks.sh` | Deploy Java and Go services to AKS |
| `deploy-to-vm.sh` | Deploy .NET service and load generator to VM |
| `vm-setup.sh` | Initial VM configuration (called by Bicep) |
| `cleanup.sh` | Delete all resources |

## Quick Start

### Complete Deployment

```bash
./deploy-all.sh otel-bugbash-rg eastus ~/.ssh/id_rsa.pub http://collector:4319 http://collector:4317
```

Parameters:
1. Resource group name
2. Azure region
3. SSH public key path
4. OTLP traces/logs endpoint URL (gRPC, default: http://localhost:4319)
5. OTLP metrics endpoint URL (gRPC, default: http://localhost:4317)

### Individual Deployments

**Deploy to AKS only:**
```bash
./deploy-to-aks.sh myacr otel-bugbash-rg otelbugbash-aks
```

**Deploy to VM only:**
```bash
./deploy-to-vm.sh <vm-ip> azureuser ~/.ssh/id_rsa
```

## Prerequisites

- Azure CLI installed and logged in
- kubectl installed
- .NET 8 SDK (for building .NET service)
- Go 1.21+ (for building Go tools)
- jq (for JSON parsing)
- SSH key pair generated

## Detailed Usage

### deploy-all.sh

Complete deployment automation:

```bash
./deploy-all.sh \
  [resource-group] \
  [location] \
  <acr-name> \
  [ssh-key-path] \
  [otel-endpoint]
```

This script:
1. Creates resource group
2. Creates Azure Container Registry
3. Deploys infrastructure (VM + AKS)
4. Builds and deploys services to AKS
5. Builds and deploys .NET service to VM
6. Configures service connectivity
7. Displays endpoints and next steps

### deploy-to-aks.sh

Deploy containerized services to AKS:

```bash
./deploy-to-aks.sh <acr-name> [aks-resource-group] [aks-cluster-name]
```

This script:
1. Builds Docker images
2. Pushes to ACR
3. Deploys to AKS
4. Waits for services to be ready
5. Retrieves service endpoints

### deploy-to-vm.sh

Deploy .NET service and load generator:

```bash
./deploy-to-vm.sh <vm-ip> [vm-user] [ssh-key]
```

This script:
1. Builds .NET service locally
2. Builds load generator locally
3. Copies binaries to VM
4. Starts systemd service
5. Verifies deployment

### vm-setup.sh

Initial VM configuration (typically called by Bicep CustomScript extension):

```bash
./vm-setup.sh [otel-endpoint] [java-service-url]
```

This script:
1. Updates system packages
2. Installs .NET 8 SDK
3. Installs Go
4. Creates application directories
5. Configures systemd service

### cleanup.sh

Delete all resources:

```bash
./cleanup.sh [resource-group]
```

⚠️ **Warning:** This deletes everything in the resource group!

## Troubleshooting

### Script Permission Errors

Make scripts executable:
```bash
chmod +x scripts/*.sh
```

### SSH Connection Issues

Test SSH connectivity:
```bash
ssh -i ~/.ssh/id_rsa azureuser@<vm-ip> "echo 'Connection successful'"
```

### ACR Access Issues

Login to ACR manually:
```bash
az acr login --name myacr
```

### Deployment Failures

Check Azure deployment status:
```bash
az deployment group show \
  --resource-group otel-bugbash-rg \
  --name main \
  --query 'properties.provisioningState'
```

View deployment errors:
```bash
az deployment group show \
  --resource-group otel-bugbash-rg \
  --name main \
  --query 'properties.error'
```

### Service Not Starting

Check service logs on VM:
```bash
ssh azureuser@<vm-ip>
sudo journalctl -u dotnet-service -f
```

Check AKS pods:
```bash
kubectl get pods
kubectl logs deployment/java-service
kubectl logs deployment/go-service
```

## Manual Deployment Steps

If scripts fail, you can deploy manually:

### 1. Infrastructure
```bash
cd infrastructure
az deployment group create \
  --resource-group otel-bugbash-rg \
  --template-file main.bicep \
  --parameters @main.parameters.json
```

### 2. AKS Services
```bash
# Build images
docker build -t myacr.azurecr.io/go-service:latest ../go-service
docker build -t myacr.azurecr.io/java-service:latest ../java-service

# Push images
docker push myacr.azurecr.io/go-service:latest
docker push myacr.azurecr.io/java-service:latest

# Deploy
kubectl apply -f ../k8s/
```

### 3. VM Service
```bash
# Build locally
cd ../dotnet-service
dotnet publish -c Release -o ./publish

# Copy to VM
scp -r publish/* azureuser@<vm-ip>:/opt/dotnet-service/

# Start service
ssh azureuser@<vm-ip> "sudo systemctl start dotnet-service"
```

## Environment Variables

Scripts use these environment variables (with defaults):

- `RESOURCE_GROUP`: Azure resource group (default: otel-bugbash-rg)
- `LOCATION`: Azure region (default: eastus)
- `ACR_NAME`: Container registry name (required)
- `OTEL_ENDPOINT`: OTLP endpoint (default: http://localhost:4318)

Set before running:
```bash
export RESOURCE_GROUP="my-rg"
export LOCATION="westus2"
export ACR_NAME="myregistry"
```
