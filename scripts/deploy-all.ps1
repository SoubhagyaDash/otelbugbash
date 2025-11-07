#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete deployment script for OpenTelemetry Bug Bash environment
.DESCRIPTION
    Deploys all infrastructure and services to Azure
.PARAMETER ResourceGroup
    Azure resource group name
.PARAMETER Location
    Azure region
.PARAMETER SshKeyPath
    Path to SSH public key
.PARAMETER OtelTracesEndpoint
    OTLP endpoint for traces and logs (gRPC)
.PARAMETER OtelMetricsEndpoint
    OTLP endpoint for metrics (gRPC)
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Azure resource group name")]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true, HelpMessage="Azure region (e.g., eastus, westus2)")]
    [string]$Location,
    
    [Parameter(Mandatory=$false)]
    [string]$SshKeyPath = "$env:USERPROFILE\.ssh\otelbugbash_rsa.pub",
    
    [Parameter(Mandatory=$false)]
    [string]$OtelTracesEndpoint = "http://localhost:4319",
    
    [Parameter(Mandatory=$false)]
    [string]$OtelMetricsEndpoint = "http://localhost:4317"
)

$ErrorActionPreference = "Stop"

# Get the script directory and project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host "=== Complete Deployment Script ===" -ForegroundColor Cyan
Write-Host "This script will deploy the entire OpenTelemetry bug bash environment"
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  Location: $Location"
Write-Host "  SSH Key: $SshKeyPath"
Write-Host "  OTLP Traces/Logs Endpoint: $OtelTracesEndpoint"
Write-Host "  OTLP Metrics Endpoint: $OtelMetricsEndpoint"
Write-Host ""
Write-Host "Note: ACR will be created automatically with a unique name"
Write-Host ""

# Create resource group
Write-Host ""
Write-Host "Step 1: Creating resource group..." -ForegroundColor Green
az group create --name $ResourceGroup --location $Location | Out-Null

# Read SSH key
Write-Host ""
Write-Host "Step 2: Reading SSH key..." -ForegroundColor Green
if (-not (Test-Path $SshKeyPath)) {
    Write-Host "Error: SSH key not found at $SshKeyPath" -ForegroundColor Red
    Write-Host "Generate one with: ssh-keygen -t rsa -b 4096 -f $env:USERPROFILE\.ssh\otelbugbash_rsa -N `"`""
    exit 1
}

$sshKey = Get-Content $SshKeyPath -Raw
$sshKey = $sshKey.Trim()

# Deploy infrastructure
Write-Host ""
Write-Host "Step 3: Deploying infrastructure (VM, AKS, ACR, networking)..." -ForegroundColor Green
Write-Host "This will take 10-15 minutes..."

$deploymentName = "otel-deployment-$(Get-Date -Format 'yyyyMMddHHmmss')"

$deploymentJson = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$ProjectRoot\infrastructure\main.bicep" `
    --parameters sshPublicKey="$sshKey" `
    --name $deploymentName `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed!" -ForegroundColor Red
    Write-Host $deploymentJson
    exit 1
}

$deployment = $deploymentJson | ConvertFrom-Json

$vmIp = $deployment.properties.outputs.vmPublicIp.value
$aksName = $deployment.properties.outputs.aksClusterName.value
$acrName = ($deployment.properties.outputs | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like '*acr*' } | Select-Object -First 1).Name
if ($acrName) {
    $acrName = $deployment.properties.outputs.$acrName.value
} else {
    # Extract ACR name from resource group
    $acrName = (az acr list --resource-group $ResourceGroup --query "[0].name" -o tsv)
}

Write-Host ""
Write-Host "Infrastructure deployed:" -ForegroundColor Green
Write-Host "  VM IP: $vmIp"
Write-Host "  AKS Name: $aksName"
Write-Host "  ACR Name: $acrName"

# Get AKS credentials
Write-Host ""
Write-Host "Step 4: Getting AKS credentials..." -ForegroundColor Green
az aks get-credentials --resource-group $ResourceGroup --name $aksName --overwrite-existing | Out-Null

# Wait for AKS to be ready
Write-Host "Waiting for AKS cluster to be ready..."
$retries = 0
while ($retries -lt 30) {
    $nodes = kubectl get nodes --no-headers 2>$null
    if ($LASTEXITCODE -eq 0 -and $nodes) {
        Write-Host "AKS cluster is ready!"
        break
    }
    Start-Sleep -Seconds 10
    $retries++
}

# Build and push container images to ACR
Write-Host ""
Write-Host "Step 5: Building and pushing container images to ACR..." -ForegroundColor Green
Write-Host "This will take 5-10 minutes..."

# Build .NET service
Write-Host "Building dotnet-service..."
az acr build --registry $acrName --image dotnet-service:latest "$ProjectRoot\dotnet-service" | Out-Null

# Build Java service
Write-Host "Building java-service..."
az acr build --registry $acrName --image java-service:latest "$ProjectRoot\java-service" | Out-Null

# Build Go service
Write-Host "Building go-service..."
az acr build --registry $acrName --image go-service:latest "$ProjectRoot\go-service" | Out-Null

# Build load generator
Write-Host "Building load-generator..."
az acr build --registry $acrName --image load-generator:latest "$ProjectRoot\load-generator" | Out-Null

$acrLoginServer = az acr show --name $acrName --query loginServer -o tsv

Write-Host ""
Write-Host "All images built and pushed to ACR: $acrLoginServer" -ForegroundColor Green

# Deploy to AKS
Write-Host ""
Write-Host "Step 6: Deploying services to AKS (Java and Go)..." -ForegroundColor Green

# Update Kubernetes manifests with ACR name
$javaManifest = Get-Content "$ProjectRoot\k8s\java-service.yaml" -Raw
$javaManifest = $javaManifest -replace 'image: .*java-service:latest', "image: $acrLoginServer/java-service:latest"
$javaManifest | Set-Content "$ProjectRoot\k8s\java-service.yaml"

$goManifest = Get-Content "$ProjectRoot\k8s\go-service.yaml" -Raw
$goManifest = $goManifest -replace 'image: .*go-service:latest', "image: $acrLoginServer/go-service:latest"
$goManifest | Set-Content "$ProjectRoot\k8s\go-service.yaml"

# Apply manifests
kubectl apply -f "$ProjectRoot\k8s\java-service.yaml" | Out-Null
kubectl apply -f "$ProjectRoot\k8s\go-service.yaml" | Out-Null

Write-Host "Waiting for Java service to get external IP..."
$retries = 0
$javaServiceIp = $null
while ($retries -lt 60) {
    $javaServiceIp = kubectl get service java-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($javaServiceIp) {
        Write-Host "Java service IP: $javaServiceIp"
        break
    }
    Start-Sleep -Seconds 5
    $retries++
}

if (-not $javaServiceIp) {
    Write-Host "Warning: Could not get Java service IP. You'll need to update .NET service manually." -ForegroundColor Yellow
    $javaServiceUrl = "http://java-service:8080"
} else {
    $javaServiceUrl = "http://${javaServiceIp}:8080"
}

# Setup VM
Write-Host ""
Write-Host "Step 7: Setting up VM with Docker and ACR credentials..." -ForegroundColor Green

$acrPassword = az acr credential show --name $acrName --query "passwords[0].value" -o tsv
$sshPrivateKey = $SshKeyPath -replace '\.pub$', ''

# Copy vm-setup.sh to VM and execute
Write-Host "Copying setup script to VM..."
scp -i $sshPrivateKey -o StrictHostKeyChecking=no "$ScriptDir\vm-setup.sh" azureuser@${vmIp}:/tmp/vm-setup.sh

Write-Host "Running setup script on VM..."
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "chmod +x /tmp/vm-setup.sh && bash /tmp/vm-setup.sh '$acrName' '$acrPassword' '$OtelTracesEndpoint' '$OtelMetricsEndpoint' '$javaServiceUrl'"

# Deploy to VM
Write-Host ""
Write-Host "Step 8: Deploying .NET service to VM..." -ForegroundColor Green

# Update docker-compose on VM and restart
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp @"
    echo '$acrPassword' | docker login ${acrName}.azurecr.io -u $acrName --password-stdin
    cd /opt/otel-bugbash
    sed -i 's|JAVA_SERVICE_URL=.*|JAVA_SERVICE_URL=${javaServiceUrl}|' docker-compose.yml
    docker compose pull
    sudo systemctl daemon-reload
    sudo systemctl enable otel-bugbash
    sudo systemctl restart otel-bugbash
"@

Start-Sleep -Seconds 5

# Verify deployment
Write-Host ""
Write-Host "Step 9: Verifying deployment..." -ForegroundColor Green

Write-Host "Checking AKS pods..."
kubectl get pods

Write-Host ""
Write-Host "Checking VM service..."
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "cd /opt/otel-bugbash && docker compose ps"

Write-Host ""
Write-Host "=== Deployment Complete! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resources:" -ForegroundColor Yellow
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  VM IP: $vmIp"
Write-Host "  AKS Cluster: $aksName"
Write-Host "  ACR: $acrName ($acrLoginServer)"
Write-Host ""
Write-Host "Service Endpoints:" -ForegroundColor Yellow
Write-Host "  .NET Service: http://${vmIp}:5000"
if ($javaServiceIp) {
    Write-Host "  Java Service: http://${javaServiceIp}:8080"
}
Write-Host ""
Write-Host "Quick Test:" -ForegroundColor Yellow
Write-Host "  curl http://${vmIp}:5000/health"
Write-Host "  curl http://${vmIp}:5000/api/process"
Write-Host ""
Write-Host "SSH to VM:" -ForegroundColor Yellow
Write-Host "  ssh -i $sshPrivateKey azureuser@$vmIp"
Write-Host ""
Write-Host "Run Load Test:" -ForegroundColor Yellow
Write-Host "  ssh -i $sshPrivateKey azureuser@$vmIp"
Write-Host "  cd /opt/otel-bugbash && ./run-load-test.sh 5m 10"
Write-Host ""
Write-Host "View Kubernetes Resources:" -ForegroundColor Yellow
Write-Host "  kubectl get all"
Write-Host "  kubectl logs -l app=java-service"
Write-Host "  kubectl logs -l app=go-service"
Write-Host ""
Write-Host "Cleanup:" -ForegroundColor Yellow
Write-Host "  az group delete --name $ResourceGroup --yes --no-wait"
Write-Host ""
