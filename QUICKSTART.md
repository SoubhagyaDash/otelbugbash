# Quick Reference Guide

## Service Architecture

```
┌─────────────────┐
│  Load Generator │ (VM)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  .NET Service   │ (VM, Port 5000)
│  + OTel SDK     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Java Service   │ (AKS, Port 8080)
│  Auto-instr.    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Go Service     │ (AKS, Port 8080)
│  + OTel SDK     │
└─────────────────┘
```

## Quick Commands

### Deployment

```PowerShell
# Select subscription
az account set --subscription "YOUR_SUBSCRIPTION_NAME"

# Full deployment (creates ACR automatically)
.\scripts\deploy-all.ps1 RESOURCE_GROUP_NAME eastus2 ~\.ssh\otelbugbash_rsa.pub http://your-collector:4318

# Get ACR name from deployment
ACR_NAME=$(az deployment group show -g otel-bugbash-rg -n main --query properties.outputs.acrName.value -o tsv)

# Deploy AKS services only
./scripts/deploy-to-aks.sh $ACR_NAME

# Deploy VM service only
VM_IP=$(az deployment group show -g otel-bugbash-rg -n main --query properties.outputs.vmPublicIp.value -o tsv)
./scripts/deploy-to-vm.sh $VM_IP $ACR_NAME
```

### Testing

```bash
# Health checks
curl http://<vm-ip>:5000/health
curl http://<java-ip>:8080/api/health
kubectl run test --image=curlimages/curl -it --rm -- curl http://go-service:8080/health

# End-to-end test
curl http://<vm-ip>:5000/api/process

# Load test
ssh azureuser@<vm-ip>
/opt/load-generator/load-generator --url http://localhost:5000/api/process --duration 10m --rate 10 --report-file report.json
```

### Monitoring

```bash
# VM service logs (Docker)
ssh azureuser@<vm-ip>
cd /opt/otel-bugbash
docker-compose logs -f dotnet-service

# Or use helper script
./view-logs.sh

# AKS service logs
kubectl logs -f deployment/java-service
kubectl logs -f deployment/go-service

# Pod status
kubectl get pods -w

# Service status
kubectl get services
```

### Troubleshooting

```bash
# Check VM Docker containers
ssh azureuser@<vm-ip> "cd /opt/otel-bugbash && docker-compose ps"

# Restart VM service
ssh azureuser@<vm-ip> "cd /opt/otel-bugbash && docker-compose restart dotnet-service"

# Update VM services from ACR
ssh azureuser@<vm-ip> "cd /opt/otel-bugbash && ./update-services.sh"

# Check AKS pod details
kubectl describe pod <pod-name>

# Get into pod for debugging
kubectl exec -it <pod-name> -- sh

# Test connectivity from VM to Java service
ssh azureuser@<vm-ip> "curl http://<java-ip>:8080/api/health"

# View ACR images
az acr repository list --name <acr-name>
```

## Environment Variables

### .NET Service (VM)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP endpoint
- `JAVA_SERVICE_URL`: Java service URL
- `ASPNETCORE_URLS`: Listen address

### Java Service (AKS)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP endpoint
- `OTEL_SERVICE_NAME`: Service name
- `GO_SERVICE_URL`: Go service URL

### Go Service (AKS)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP endpoint
- `PORT`: HTTP port

## Common Issues

### Can't connect to Java service from VM
```bash
# Get Java service external IP
kubectl get service java-service

# Update .NET service configuration
ssh azureuser@<vm-ip>
sudo vi /etc/systemd/system/dotnet-service.service
# Update JAVA_SERVICE_URL
sudo systemctl daemon-reload
sudo systemctl restart dotnet-service
```

### No traces appearing
1. Check OTLP endpoint is reachable
2. Verify exporters are configured
3. Check service logs for export errors
4. Verify network connectivity

### High latency
1. Check resource utilization
2. Scale up replicas
3. Verify network performance
4. Check OTLP collector performance

## Resource Cleanup

### Complete Teardown (Recommended)

Delete all resources with one command:

```bash
cd scripts
./cleanup.sh otel-bugbash-rg
```

**What gets deleted:**
- Azure Container Registry and all images
- Virtual Machine (.NET service)
- AKS Cluster (Java and Go services)
- All networking (VNet, NSG, Public IPs)
- All associated resources

**Timeline:** 5-15 minutes

**Verification:**
```bash
# Check if deletion is complete (will error when done)
az group show --name otel-bugbash-rg
```

### Manual Deletion

```bash
# Delete resource group directly
az group delete --name otel-bugbash-rg --yes --no-wait
```

### Local Cleanup (Optional)

```bash
# Remove SSH keys
rm ~/.ssh/otelbugbash_rsa*

# Remove repository
cd ..
rm -rf OtelBugBash
```

## Useful URLs

- VM Service: http://\<vm-ip\>:5000
- Java Service: http://\<java-ip\>:8080
- Azure Portal: https://portal.azure.com
- AKS Dashboard: `az aks browse -g otel-bugbash-rg -n otelbugbash-aks`
