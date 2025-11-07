#!/bin/bash
set -e

echo "=== Complete Deployment Script ==="
echo "This script will deploy the entire OpenTelemetry bug bash environment"
echo ""

# Configuration
RESOURCE_GROUP="${1:-otel-bugbash-rg}"
LOCATION="${2:-eastus}"
SSH_KEY_PATH="${3:-~/.ssh/otelbugbash_rsa.pub}"
OTEL_TRACES_ENDPOINT="${4:-http://localhost:4319}"
OTEL_METRICS_ENDPOINT="${5:-http://localhost:4317}"

echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  SSH Key: $SSH_KEY_PATH"
echo "  OTLP Traces/Logs Endpoint: $OTEL_TRACES_ENDPOINT"
echo "  OTLP Metrics Endpoint: $OTEL_METRICS_ENDPOINT"
echo ""
echo "Note: ACR will be created automatically with a unique name"
echo ""

read -p "Continue with deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 1
fi

# Create resource group
echo ""
echo "Step 1: Creating resource group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Read SSH key
echo ""
echo "Step 2: Reading SSH key..."
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH key not found at $SSH_KEY_PATH"
    echo "Generate one with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/otelbugbash_rsa"
    exit 1
fi
SSH_KEY=$(cat "$SSH_KEY_PATH")

# Deploy infrastructure (including ACR)
echo ""
echo "Step 3: Deploying infrastructure with Bicep (including ACR)..."
cd ../infrastructure
DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file main.bicep \
    --parameters location="$LOCATION" \
    --parameters otelEndpoint="$OTEL_ENDPOINT" \
    --parameters sshPublicKey="$SSH_KEY" \
    --parameters namePrefix="otelbugbash" \
    --query 'properties.outputs' \
    --output json)

VM_IP=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.vmPublicIp.value')
AKS_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.aksClusterName.value')
ACR_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.acrName.value')
ACR_LOGIN_SERVER=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.acrLoginServer.value')

echo "Infrastructure deployed!"
echo "  VM IP: $VM_IP"
echo "  AKS Cluster: $AKS_NAME"
echo "  ACR Name: $ACR_NAME"
echo "  ACR Login Server: $ACR_LOGIN_SERVER"

# Wait for VM to be ready
echo ""
echo "Step 4: Waiting for VM to be ready..."
sleep 30

# Build and push all container images to ACR
echo ""
echo "Step 5: Building and pushing container images to ACR..."
cd ../scripts
./deploy-to-aks.sh "$ACR_NAME" "$RESOURCE_GROUP" "$AKS_NAME"

# Get Java service IP
echo ""
echo "Step 6: Getting Java service external IP..."
JAVA_SERVICE_IP=""
for i in {1..30}; do
    JAVA_SERVICE_IP=$(kubectl get service java-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$JAVA_SERVICE_IP" ]; then
        break
    fi
    echo "  Attempt $i/30: Waiting..."
    sleep 10
done

if [ -z "$JAVA_SERVICE_IP" ]; then
    echo "Warning: Could not get Java service IP. You'll need to update .NET service manually."
    JAVA_SERVICE_URL="http://java-service:8080"
else
    echo "Java Service IP: $JAVA_SERVICE_IP"
    JAVA_SERVICE_URL="http://$JAVA_SERVICE_IP:8080"
fi

# Get ACR credentials for VM setup
echo ""
echo "Step 7: Setting up VM with ACR credentials..."
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)

SSH_PRIVATE_KEY="${SSH_KEY_PATH%.pub}"
ssh -i "$SSH_PRIVATE_KEY" azureuser@"$VM_IP" "bash -s" <<REMOTE_SCRIPT
    $(cat ../scripts/vm-setup.sh)
    
    # Run setup
    bash vm-setup.sh "$ACR_NAME" "$ACR_PASSWORD" "$OTEL_TRACES_ENDPOINT" "$OTEL_METRICS_ENDPOINT" "$JAVA_SERVICE_URL"
REMOTE_SCRIPT

# Deploy services to VM
echo ""
echo "Step 8: Deploying services to VM..."
./deploy-to-vm.sh "$VM_IP" "$ACR_NAME"

echo ""
echo "=== Deployment Complete! ==="
echo ""
echo "Resources:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  VM IP: $VM_IP"
echo "  AKS Cluster: $AKS_NAME"
echo "  ACR: $ACR_NAME ($ACR_LOGIN_SERVER)"
echo ""
echo "Service Endpoints:"
echo "  .NET Service: http://$VM_IP:5000"
echo "  Java Service: http://$JAVA_SERVICE_IP:8080"
echo "  Go Service: (internal only)"
echo ""
echo "Container Images in ACR:"
echo "  $ACR_LOGIN_SERVER/dotnet-service:latest"
echo "  $ACR_LOGIN_SERVER/java-service:latest"
echo "  $ACR_LOGIN_SERVER/go-service:latest"
echo "  $ACR_LOGIN_SERVER/load-generator:latest"
echo ""
echo "Next Steps:"
echo "1. Verify .NET service: curl http://$VM_IP:5000/health"
echo "2. Verify Java service: curl http://$JAVA_SERVICE_IP:8080/api/health"
echo "3. Test end-to-end: curl http://$VM_IP:5000/api/process"
echo "4. Run load test:"
echo "   ssh -i $SSH_PRIVATE_KEY azureuser@$VM_IP"
echo "   cd /opt/otel-bugbash"
echo "   ./run-load-test.sh 10m 10"
echo ""
echo "View logs:"
echo "   ssh -i $SSH_PRIVATE_KEY azureuser@$VM_IP"
echo "   cd /opt/otel-bugbash && ./view-logs.sh"
echo ""
echo "Documentation: See BUGBASH_INSTRUCTIONS.md for detailed testing scenarios"
