# Azure Infrastructure

Bicep templates for deploying the OpenTelemetry bug bash environment.

## Resources Deployed

1. **Azure Container Registry (ACR)** - Stores all container images
2. **Virtual Network** with subnets for VM and AKS
3. **Linux VM** (Ubuntu 22.04 LTS)
   - Docker installed
   - .NET service running in container
   - Load generator available as container
4. **AKS Cluster** with 2 nodes
   - Java and Go services running as containers
   - Auto-configured to pull from ACR
5. **Network Security Group** with SSH and HTTP access
6. **Public IP** for VM access

## Prerequisites

- Azure CLI installed
- Bicep CLI installed
- SSH key pair generated
- kubectl installed
- jq installed (for JSON parsing)

## Generate SSH Key

If you don't have an SSH key:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/otelbugbash_rsa
```

## Deployment

### Simple Deployment (Recommended)

Use the automated deployment script:

```bash
cd ../scripts
./deploy-all.sh otel-bugbash-rg eastus ~/.ssh/otelbugbash_rsa.pub http://your-collector:4318
```

This will:
- Create resource group
- Deploy ACR (with auto-generated unique name)
- Deploy VM and AKS
- Build and push all container images
- Deploy services to VM and AKS

### Manual Deployment

#### Option 1: Using Azure CLI

```bash
# Get your SSH public key
SSH_KEY=$(cat ~/.ssh/otelbugbash_rsa.pub)

# Deploy (ACR name will be auto-generated)
az deployment group create \
  --resource-group otel-bugbash-rg \
  --template-file main.bicep \
  --parameters location=eastus \
  --parameters otelEndpoint=http://your-collector:4318 \
  --parameters sshPublicKey="$SSH_KEY" \
  --parameters namePrefix=otelbugbash
```

#### Option 2: Using Parameters File

1. Edit `main.parameters.json`
2. Replace `YOUR_SSH_PUBLIC_KEY_HERE` with your actual SSH public key
3. Update other parameters as needed
4. Deploy:

```bash
az deployment group create \
  --resource-group otel-bugbash-rg \
  --template-file main.bicep \
  --parameters @main.parameters.json
```

## Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| location | Azure region | Resource group location | No |
| otelEndpoint | OTLP endpoint URL | http://localhost:4318 | No |
| adminUsername | VM admin username | azureuser | No |
| sshPublicKey | SSH public key for VM | - | Yes |
| namePrefix | Resource name prefix | otelbugbash | No |
| acrName | ACR name (must be globally unique) | Auto-generated | No |

## Outputs

After deployment, you'll receive:

- `vmPublicIp`: VM public IP address
- `vmFqdn`: VM fully qualified domain name
- `aksClusterName`: AKS cluster name
- `aksResourceGroup`: Resource group name
- `sshCommand`: SSH command to connect to VM
- `acrName`: Azure Container Registry name
- `acrLoginServer`: ACR login server URL

## Post-Deployment Steps

**If using automated script (`deploy-all.sh`), these are done automatically.**

For manual deployment:

1. **Build and push images to ACR:**
   ```bash
   cd ../scripts
   ACR_NAME=$(az deployment group show -g otel-bugbash-rg -n main --query properties.outputs.acrName.value -o tsv)
   ./deploy-to-aks.sh "$ACR_NAME"
   ```

2. **Deploy to VM:**
   ```bash
   VM_IP=$(az deployment group show -g otel-bugbash-rg -n main --query properties.outputs.vmPublicIp.value -o tsv)
   ./deploy-to-vm.sh "$VM_IP" "$ACR_NAME"
   ```

3. **Verify deployments:**
   ```bash
   # Check AKS
   kubectl get pods
   kubectl get services
   
   # Check VM
   ssh azureuser@$VM_IP
   cd /opt/otel-bugbash && docker-compose ps
   ```

## Estimated Costs

- VM (Standard_D2s_v3): ~$70/month
- AKS (2x Standard_D2s_v3): ~$140/month
- ACR (Basic): ~$5/month
- Total: ~$215/month

Stop resources when not in use to reduce costs.

## Container Images

All services are containerized and stored in ACR:

- `dotnet-service:latest` - .NET 8 Web API with OTel SDK
- `java-service:latest` - Spring Boot with OTel auto-instrumentation
- `go-service:latest` - Go service with OTel SDK
- `load-generator:latest` - Load testing tool

Images are automatically built and pushed during deployment.

## Cleanup

To remove all resources:

```bash
az group delete --name otel-bugbash-rg --yes --no-wait
```
