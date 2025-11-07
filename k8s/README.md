# Kubernetes Manifests

Kubernetes deployment and service configurations for AKS.

## Services

### Go Service
- **Replicas**: 2
- **Type**: ClusterIP (internal only)
- **Port**: 8080
- **Instrumentation**: Manual OpenTelemetry SDK

### Java Service
- **Replicas**: 2
- **Type**: LoadBalancer (accessible from VM)
- **Port**: 8080
- **Instrumentation**: Auto-instrumentation via Java agent

## Prerequisites

- AKS cluster deployed
- kubectl configured
- Container images built and pushed to registry

## Building and Pushing Images

### Option 1: Using Azure Container Registry

```bash
# Login to ACR
az acr login --name your-acr

# Build and push Go service
cd ../go-service
docker build -t your-acr.azurecr.io/go-service:latest .
docker push your-acr.azurecr.io/go-service:latest

# Build and push Java service
cd ../java-service
docker build -t your-acr.azurecr.io/java-service:latest .
docker push your-acr.azurecr.io/java-service:latest
```

### Option 2: Using ACR Build Tasks

```bash
# Build Go service
az acr build --registry your-acr --image go-service:latest ../go-service

# Build Java service
az acr build --registry your-acr --image java-service:latest ../java-service
```

## Updating Manifests

Before deploying, update the following in the YAML files:

1. Replace `your-acr.azurecr.io` with your actual ACR name
2. Update `OTEL_EXPORTER_OTLP_ENDPOINT` with your OTLP collector endpoint

## Deployment

### Deploy All Services

```bash
kubectl apply -f go-service.yaml
kubectl apply -f java-service.yaml
```

### Verify Deployment

```bash
# Check pod status
kubectl get pods

# Check services
kubectl get services

# View logs
kubectl logs -f deployment/go-service
kubectl logs -f deployment/java-service
```

### Get Java Service External IP

Since the Java service is exposed as LoadBalancer (needed by .NET service on VM):

```bash
kubectl get service java-service

# Wait for EXTERNAL-IP to be assigned
# This IP will be used by the .NET service
```

## Scaling

Scale deployments as needed:

```bash
# Scale Go service
kubectl scale deployment go-service --replicas=3

# Scale Java service
kubectl scale deployment java-service --replicas=3
```

## Troubleshooting

### Pods Not Starting

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Image Pull Errors

Attach ACR to AKS:

```bash
az aks update \
  --resource-group otel-bugbash-rg \
  --name otelbugbash-aks \
  --attach-acr your-acr
```

### Service Not Reachable

```bash
# Test from within cluster
kubectl run test-pod --image=curlimages/curl -it --rm -- sh
curl http://go-service:8080/health
curl http://java-service:8080/api/health
```

### View OpenTelemetry Logs

```bash
# Java service (check auto-instrumentation)
kubectl logs deployment/java-service | grep -i otel

# Go service
kubectl logs deployment/go-service | grep -i otel
```

## Environment Variables

### Go Service
- `PORT`: HTTP server port (default: 8080)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP endpoint

### Java Service
- `JAVA_TOOL_OPTIONS`: JVM options including Java agent
- `OTEL_SERVICE_NAME`: Service name for traces
- `OTEL_TRACES_EXPORTER`: Trace exporter type
- `OTEL_EXPORTER_OTLP_PROTOCOL`: OTLP protocol
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP endpoint
- `GO_SERVICE_URL`: Go service URL

## Update Deployments

After changing manifests:

```bash
kubectl apply -f go-service.yaml
kubectl apply -f java-service.yaml

# Force rollout
kubectl rollout restart deployment/go-service
kubectl rollout restart deployment/java-service
```

## Cleanup

```bash
kubectl delete -f go-service.yaml
kubectl delete -f java-service.yaml
```
