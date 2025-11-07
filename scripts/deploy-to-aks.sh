#!/bin/bash
set -e

echo "=== Deploying Services to AKS ==="

# Configuration
ACR_NAME="${1}"
AKS_RG="${2:-otel-bugbash-rg}"
AKS_NAME="${3:-otelbugbash-aks}"

if [ -z "$ACR_NAME" ]; then
    echo "Error: ACR name is required"
    echo "Usage: $0 <acr-name> [aks-resource-group] [aks-cluster-name]"
    exit 1
fi

echo "ACR Name: $ACR_NAME"
echo "AKS Resource Group: $AKS_RG"
echo "AKS Cluster: $AKS_NAME"

# Login to ACR
echo "Logging in to Azure Container Registry..."
az acr login --name "$ACR_NAME"

# Build and push all services
echo "Building and pushing .NET service..."
cd ../dotnet-service
az acr build --registry "$ACR_NAME" --image dotnet-service:latest .

echo "Building and pushing Go service..."
cd ../go-service
az acr build --registry "$ACR_NAME" --image go-service:latest .

echo "Building and pushing Java service..."
cd ../java-service
az acr build --registry "$ACR_NAME" --image java-service:latest .

echo "Building and pushing load generator..."
cd ../load-generator
az acr build --registry "$ACR_NAME" --image load-generator:latest .

# Get AKS credentials
echo "Getting AKS credentials..."
az aks get-credentials \
    --resource-group "$AKS_RG" \
    --name "$AKS_NAME" \
    --overwrite-existing

# Update manifests with ACR name
echo "Updating Kubernetes manifests..."
cd ../k8s
cp go-service.yaml go-service.yaml.bak
cp java-service.yaml java-service.yaml.bak

sed -i.tmp "s|your-acr.azurecr.io|$ACR_NAME.azurecr.io|g" go-service.yaml
sed -i.tmp "s|your-acr.azurecr.io|$ACR_NAME.azurecr.io|g" java-service.yaml
rm -f *.tmp

# Deploy to AKS
echo "Deploying to AKS..."
kubectl apply -f go-service.yaml
kubectl apply -f java-service.yaml

# Wait for deployments
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/go-service
kubectl wait --for=condition=available --timeout=300s deployment/java-service

# Restore original manifests
mv go-service.yaml.bak go-service.yaml
mv java-service.yaml.bak java-service.yaml

# Get service information
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Pod Status:"
kubectl get pods

echo ""
echo "Service Status:"
kubectl get services

echo ""
echo "Waiting for Java service external IP..."
for i in {1..30}; do
    JAVA_SERVICE_IP=$(kubectl get service java-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$JAVA_SERVICE_IP" ]; then
        echo "Java Service External IP: $JAVA_SERVICE_IP"
        break
    fi
    echo "  Attempt $i/30: Waiting..."
    sleep 10
done

if [ -z "$JAVA_SERVICE_IP" ]; then
    echo "Warning: External IP not assigned yet. Check later with:"
    echo "  kubectl get service java-service --watch"
else
    echo ""
    echo "Java Service URL: http://$JAVA_SERVICE_IP:8080"
    echo "Update your .NET service with this URL"
    echo ""
    echo "Test endpoints:"
    echo "  curl http://$JAVA_SERVICE_IP:8080/api/health"
fi

echo ""
echo "Internal testing:"
echo "  kubectl run test --image=curlimages/curl -it --rm -- curl http://go-service:8080/health"
