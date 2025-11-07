# ACR Integration Summary

## What Changed

The OpenTelemetry bug bash environment now includes **Azure Container Registry (ACR)** as a central component for storing and distributing all container images.

## Key Improvements

### 1. **Automated ACR Creation**
- ACR is now created automatically by the Bicep template
- Unique name is auto-generated (no naming conflicts)
- AKS is automatically configured to pull from ACR

### 2. **Fully Containerized Deployment**
All services now run as containers:
- ✅ **Go Service** - Runs in AKS from ACR
- ✅ **Java Service** - Runs in AKS from ACR
- ✅ **.NET Service** - Runs on VM via Docker Compose from ACR
- ✅ **Load Generator** - Available as container on VM from ACR

### 3. **Simplified VM Deployment**
VM now uses Docker Compose instead of systemd:
- All services defined in `docker-compose.yml`
- Easy to update: `./update-services.sh`
- Consistent with AKS deployment
- Better isolation and resource management

### 4. **Streamlined Build & Push**
- All images built using `az acr build` (cloud-based builds)
- No local Docker required for deployment
- Automatic image versioning
- Single source of truth for all images

## Updated Architecture

```
┌──────────────────────────────────────────┐
│  Azure Container Registry (ACR)          │
│  - dotnet-service:latest                 │
│  - java-service:latest                   │
│  - go-service:latest                     │
│  - load-generator:latest                 │
└──────────────┬────────────────┬──────────┘
               │                │
       ┌───────▼──────┐  ┌─────▼──────────┐
       │   VM (Docker) │  │  AKS Cluster   │
       │  - .NET svc   │  │  - Java svc    │
       │  - Load gen   │  │  - Go svc      │
       └───────────────┘  └────────────────┘
```

## New Components

### On VM (`/opt/otel-bugbash/`)

**docker-compose.yml**
```yaml
services:
  dotnet-service:
    image: {acr}.azurecr.io/dotnet-service:latest
    ports: ["5000:5000"]
  load-generator:
    image: {acr}.azurecr.io/load-generator:latest
    profiles: ["tools"]
```

**Helper Scripts**
- `run-load-test.sh [duration] [rate]` - Run load tests
- `view-logs.sh` - View service logs
- `update-services.sh` - Pull and restart services

### Bicep Changes

Added:
- ACR resource definition
- Role assignment for AKS → ACR pull access
- ACR name and login server outputs

### Deployment Script Changes

**deploy-all.sh**
- No longer requires ACR name as parameter (auto-created)
- Builds all 4 images and pushes to ACR
- Configures VM with ACR credentials

**deploy-to-aks.sh**
- Now builds all images including load-generator
- Uses `az acr build` for cloud-based builds

**deploy-to-vm.sh**
- Deploys via Docker Compose
- Configures ACR authentication
- Sets up helper scripts

## Usage Changes

### Before (Without ACR)
```bash
# Had to specify ACR name manually
./deploy-all.sh otel-bugbash-rg eastus myacr ~/.ssh/key.pub

# Needed local Docker builds
# Needed to manually manage ACR
```

### After (With Integrated ACR)
```bash
# ACR created automatically, simpler command
./deploy-all.sh otel-bugbash-rg eastus ~/.ssh/key.pub http://collector:4318

# Everything handled automatically:
# ✅ ACR creation
# ✅ Image builds in cloud
# ✅ Image pushes
# ✅ Deployments
```

## Benefits

1. **Consistency** - All services use the same deployment pattern
2. **Simplicity** - Fewer manual steps, more automation
3. **Reliability** - Cloud builds are more consistent
4. **Scalability** - Easy to add new services
5. **Maintainability** - Update all services with one command
6. **Security** - Managed identities for AKS→ACR access

## Cost Impact

- **ACR Basic tier**: ~$5/month
- **Total estimated cost**: ~$215/month (was ~$210)

## Migration Notes

For existing deployments:
1. ACR will be created on next deployment
2. VM will be reconfigured to use Docker
3. All services will be containerized
4. No data loss (fresh deployment recommended)

## Testing

Verify ACR integration:
```bash
# Check ACR exists
az acr show --name <acr-name>

# List images
az acr repository list --name <acr-name>

# Check VM is pulling from ACR
ssh azureuser@<vm-ip>
cd /opt/otel-bugbash
docker-compose images

# Check AKS is using ACR images
kubectl describe pod <pod-name> | grep Image
```

## Troubleshooting

**Issue**: VM can't pull images from ACR
```bash
# Re-login to ACR on VM
ACR_PASS=$(az acr credential show --name <acr> --query "passwords[0].value" -o tsv)
ssh azureuser@<vm-ip>
echo $ACR_PASS | docker login <acr>.azurecr.io -u <acr> --password-stdin
```

**Issue**: AKS can't pull images from ACR
```bash
# Reattach ACR to AKS
az aks update --resource-group <rg> --name <aks> --attach-acr <acr>
```

**Issue**: Images not found in ACR
```bash
# Rebuild and push
cd scripts
./deploy-to-aks.sh <acr-name>
```
