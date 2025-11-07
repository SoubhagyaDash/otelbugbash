# OpenTelemetry Bug Bash - Detailed Instructions

## Overview

This bug bash environment tests OpenTelemetry distributed tracing across multiple services and platforms.

## Architecture Flow

```
Load Generator --> .NET API (VM) --> Java API (AKS) --> Go API (AKS)
```

## Prerequisites

Before you begin, ensure you have:

- [ ] Azure subscription with contributor access
- [ ] Azure CLI installed and configured
- [ ] kubectl installed
- [ ] SSH client (for VM access)
- [ ] Git installed

## Deployment Steps

### 1. Clone and Prepare

```bash
git clone <repository-url>
cd OtelBugBash
```

### 2. Set Environment Variables

```bash
# Set your Azure details
export RESOURCE_GROUP="otel-bugbash-rg"
export LOCATION="eastus"
export OTEL_ENDPOINT="<your-otel-collector-endpoint>"  # e.g., http://your-collector:4318
```

### 3. Create Resource Group

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### 4. Deploy Infrastructure

```bash
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file infrastructure/main.bicep \
  --parameters location=$LOCATION \
  --parameters otelEndpoint=$OTEL_ENDPOINT
```

This will deploy:
- Azure Kubernetes Service (AKS) cluster
- Linux VM for .NET service
- Network infrastructure
- Container Registry (if needed)

### 5. Get Deployment Outputs

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name <aks-cluster-name>

# Get VM public IP
VM_IP=$(az vm show \
  --resource-group $RESOURCE_GROUP \
  --name <vm-name> \
  --show-details \
  --query publicIps -o tsv)

echo "VM IP: $VM_IP"
```

### 6. Deploy AKS Services

```bash
# Apply Kubernetes manifests
kubectl apply -f k8s/go-service.yaml
kubectl apply -f k8s/java-service.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=go-service --timeout=300s
kubectl wait --for=condition=ready pod -l app=java-service --timeout=300s

# Get service endpoints
kubectl get services
```

### 7. Verify VM Setup

```bash
# SSH into the VM
ssh azureuser@$VM_IP

# Verify .NET service is running
sudo systemctl status dotnet-service

# Verify load generator is installed
/opt/load-generator/load-generator --version
```

## Running the Bug Bash

### 1. Start Load Generation

SSH into the VM and run:

```bash
sudo /opt/load-generator/load-generator \
  --url http://localhost:5000/api/process \
  --duration 10m \
  --rate 10 \
  --report-file /tmp/load-test-report.json
```

Parameters:
- `--duration`: How long to run (e.g., 10m, 1h)
- `--rate`: Requests per second
- `--report-file`: Where to save the report

### 2. Monitor Services

**Check .NET Service Logs:**
```bash
ssh azureuser@$VM_IP
sudo journalctl -u dotnet-service -f
```

**Check Java Service Logs:**
```bash
kubectl logs -f deployment/java-service
```

**Check Go Service Logs:**
```bash
kubectl logs -f deployment/go-service
```

### 3. View Results

After the load test completes, retrieve the report:

```bash
scp azureuser@$VM_IP:/tmp/load-test-report.json ./load-test-report.json
cat load-test-report.json
```

The report includes:
- Total requests sent
- Successful requests
- Failed requests
- Latency percentiles (p50, p90, p95, p99)
- Error details

## Testing Scenarios

### Scenario 1: Basic End-to-End Tracing

1. Send a single request through the chain
2. Verify trace appears in your observability backend
3. Confirm all 3 services appear in the trace
4. Verify span relationships (parent-child)

**Test Command:**
```bash
curl http://$VM_IP:5000/api/process
```

### Scenario 2: Load Testing

1. Run load generator for 10 minutes at 10 req/sec
2. Monitor trace collection rate
3. Check for dropped traces
4. Verify performance metrics

### Scenario 3: Auto-instrumentation Validation

1. Verify Java service has NO manual instrumentation code
2. Confirm traces still appear from Java service
3. Check auto-instrumentation quality (span names, attributes)

### Scenario 4: Error Propagation

1. Trigger an error in the Go service
2. Verify error propagates through Java and .NET
3. Check error attributes in traces
4. Verify error status is recorded correctly

**Trigger Error:**
```bash
curl http://$VM_IP:5000/api/process?error=true
```

### Scenario 5: High Load Stress Test

1. Increase load to 100 req/sec
2. Monitor for trace sampling issues
3. Check for performance degradation
4. Verify traces remain consistent

## Troubleshooting

### VM Service Not Running

```bash
ssh azureuser@$VM_IP
sudo systemctl restart dotnet-service
sudo journalctl -u dotnet-service -n 50
```

### AKS Pods Not Starting

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### No Traces Appearing

1. Verify OTLP endpoint is reachable from all services
2. Check service logs for export errors
3. Verify network connectivity between services

```bash
# Test from VM
curl -v http://<java-service-ip>:8080/health

# Test from Java pod
kubectl exec -it <java-pod> -- curl http://go-service:8080/health
```

### Load Generator Issues

```bash
# Check if load generator is installed
ssh azureuser@$VM_IP
ls -la /opt/load-generator/

# Run manually
/opt/load-generator/load-generator --url http://localhost:5000/api/process --duration 1m --rate 1
```

## Cleanup

### Complete Teardown

After completing the bug bash, delete all Azure resources with one command:

```bash
cd scripts
./cleanup.sh otel-bugbash-rg
```

This script will:
- ✅ Prompt for confirmation (type "yes" to confirm)
- ✅ Delete the entire resource group and all contained resources
- ✅ Remove: VM, AKS cluster, ACR, networking, and all associated resources
- ✅ Stop all billing

**Deletion timeline:** 5-15 minutes (runs asynchronously)

**Check deletion status:**
```bash
# Will error when deletion is complete
az group show --name otel-bugbash-rg
```

### Optional: Local Cleanup

```bash
# Remove SSH keys (if you want to delete them)
rm ~/.ssh/otelbugbash_rsa*

# Remove cloned repository (optional)
rm -rf ~/OtelBugBash
```

### Manual Alternative

If you prefer to use Azure CLI directly:

```bash
az group delete --name otel-bugbash-rg --yes --no-wait
```

## Bug Reporting

When you find issues, please report:

1. **Issue Description**: What went wrong?
2. **Steps to Reproduce**: How to recreate the issue?
3. **Expected Behavior**: What should happen?
4. **Actual Behavior**: What actually happened?
5. **Logs**: Include relevant logs from services
6. **Trace ID**: If applicable, include trace IDs
7. **Environment**: Service name, timestamp, configuration

## Support

For questions or issues during the bug bash, contact [your-team-email].
