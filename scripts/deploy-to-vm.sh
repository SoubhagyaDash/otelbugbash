#!/bin/bash
set -e

echo "=== Deploying Services to VM ==="

# Configuration
VM_IP="${1}"
ACR_NAME="${2}"
VM_USER="${3:-azureuser}"
SSH_KEY="${4:-~/.ssh/otelbugbash_rsa}"

if [ -z "$VM_IP" ] || [ -z "$ACR_NAME" ]; then
    echo "Error: VM IP and ACR name are required"
    echo "Usage: $0 <vm-ip> <acr-name> [vm-user] [ssh-key]"
    exit 1
fi

echo "VM IP: $VM_IP"
echo "ACR Name: $ACR_NAME"
echo "VM User: $VM_USER"
echo "SSH Key: $SSH_KEY"

# Get ACR credentials
echo "Getting ACR credentials..."
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)

# Get Java service URL from AKS
echo "Getting Java service external IP..."
JAVA_SERVICE_IP=$(kubectl get service java-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -z "$JAVA_SERVICE_IP" ]; then
    echo "Warning: Java service IP not found. Using default."
    JAVA_SERVICE_URL="http://java-service:8080"
else
    JAVA_SERVICE_URL="http://$JAVA_SERVICE_IP:8080"
    echo "Java Service URL: $JAVA_SERVICE_URL"
fi

# Setup VM with ACR credentials and configuration
echo "Configuring VM..."
ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "bash -s" <<REMOTE_SCRIPT
    # Login to ACR
    echo "$ACR_PASSWORD" | docker login "${ACR_NAME}.azurecr.io" -u "$ACR_NAME" --password-stdin
    
    # Update docker compose with correct Java service URL
    cd /opt/otel-bugbash
    sed -i "s|JAVA_SERVICE_URL=.*|JAVA_SERVICE_URL=${JAVA_SERVICE_URL}|" docker-compose.yml
    
    # Pull latest images
    docker compose pull
    
    # Start services
    sudo systemctl daemon-reload
    sudo systemctl enable otel-bugbash
    sudo systemctl restart otel-bugbash
REMOTE_SCRIPT

# Wait for service to start
echo "Waiting for service to start..."
sleep 5

# Check status
echo "Checking service status..."
ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "cd /opt/otel-bugbash && docker compose ps"

echo ""
echo "=== Deployment Complete ==="
echo "Service endpoint: http://$VM_IP:5000"
echo ""
echo "Verify deployment:"
echo "  curl http://$VM_IP:5000/health"
echo ""
echo "View logs:"
echo "  ssh -i $SSH_KEY $VM_USER@$VM_IP"
echo "  cd /opt/otel-bugbash && ./view-logs.sh"
echo ""
echo "Run load test:"
echo "  ssh -i $SSH_KEY $VM_USER@$VM_IP"
echo "  cd /opt/otel-bugbash && ./run-load-test.sh 10m 10"
