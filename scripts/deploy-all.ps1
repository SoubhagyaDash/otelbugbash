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

Write-Host "Upgrading Azure CLI and extensions..." -ForegroundColor Green

# Upgrade Azure CLI
az upgrade

# Upgrade extensions (same command)
az upgrade

# Login to Azure CLI (no subscription prompt)
az login

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
az group create --name $ResourceGroup --location $Location `
    --tags SkipLinuxAzSecPack=True SkipASMAzSecPack=True SkipWindowsAzSecPack=True | Out-Null

# Assign Owner role to OtelAksVmBugBashers group
Write-Host "Assigning Owner role to OtelAksVmBugBashers group..."
$groupObjectId = az ad group show --group "OtelAksVmBugBashers" --query id -o tsv
if ($groupObjectId) {
    az role assignment create --assignee-object-id $groupObjectId `
        --assignee-principal-type Group `
        --role Owner `
        --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup" | Out-Null
    Write-Host "Owner role assigned successfully" -ForegroundColor Green
} else {
    Write-Host "Warning: Could not find group 'OtelAksVmBugBashers'. Skipping role assignment." -ForegroundColor Yellow
}

# Read or generate SSH key
Write-Host ""
Write-Host "Step 2: Checking SSH key..." -ForegroundColor Green

# Expand tilde to full path
$SshKeyPath = $SshKeyPath -replace '^~', $env:USERPROFILE

if (-not (Test-Path $SshKeyPath)) {
    Write-Host "SSH key not found at $SshKeyPath" -ForegroundColor Yellow
    Write-Host "Generating new SSH key pair without passphrase for automation..." -ForegroundColor Green
    
    # Get the private key path (remove .pub extension)
    $sshPrivateKeyPath = $SshKeyPath -replace '\.pub$', ''
    
    # Create .ssh directory if it doesn't exist
    $sshDir = Split-Path -Parent $sshPrivateKeyPath
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
    
    # Generate SSH key pair with no passphrase for automation
    ssh-keygen -t rsa -b 4096 -f $sshPrivateKeyPath -N "" -C "otelbugbash@azure"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to generate SSH key" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "SSH key pair generated successfully!" -ForegroundColor Green
    Write-Host "  Private key: $sshPrivateKeyPath"
    Write-Host "  Public key: $SshKeyPath"
}

$sshKey = Get-Content $SshKeyPath -Raw
$sshKey = $sshKey.Trim()

# Deploy infrastructure
Write-Host ""
Write-Host "Step 3: Deploying infrastructure (VM, AKS, ACR, networking)..." -ForegroundColor Green
Write-Host "This will take 10-15 minutes..."

$deploymentName = "otel-deployment-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Create a temporary parameters file with the SSH key
$paramsFile = [System.IO.Path]::GetTempFileName()
$parametersObject = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
        sshPublicKey = @{
            value = $sshKey
        }
        vmSize = @{
            value = 'Standard_D2ds_v5'
        }
        aksNodeSize = @{
            value = 'Standard_D2ds_v5'
        }
    }
}
$parametersObject | ConvertTo-Json -Depth 10 | Set-Content -Path $paramsFile -Encoding UTF8

try {
    # Deploy infrastructure
    $deploymentJson = az deployment group create `
        --resource-group $ResourceGroup `
        --template-file "$ProjectRoot\infrastructure\main.bicep" `
        --parameters "@$paramsFile" `
        --name $deploymentName `
        --output json
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Infrastructure deployment failed!" -ForegroundColor Red
        exit 1
    }
    
    $deployment = $deploymentJson | ConvertFrom-Json
}
finally {
    if (Test-Path $paramsFile) {
        Remove-Item $paramsFile -Force
    }
}

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

# Start building and pushing container images to ACR in parallel (while AKS is getting ready)
Write-Host ""
Write-Host "Step 4a: Starting parallel container image builds to ACR..." -ForegroundColor Green
Write-Host "These will run in the background while we set up AKS..."

# Start all builds in parallel using background jobs
$jobs = @()

Write-Host "  - Starting dotnet-service build..."
$jobs += Start-Job -ScriptBlock {
    param($acrName, $projectRoot)
    az acr build --registry $acrName --image dotnet-service:latest "$projectRoot\dotnet-service"
} -ArgumentList $acrName, $ProjectRoot

Write-Host "  - Starting java-service build..."
$jobs += Start-Job -ScriptBlock {
    param($acrName, $projectRoot)
    az acr build --registry $acrName --image java-service:latest "$projectRoot\java-service"
} -ArgumentList $acrName, $ProjectRoot

Write-Host "  - Starting go-service build..."
$jobs += Start-Job -ScriptBlock {
    param($acrName, $projectRoot)
    az acr build --registry $acrName --image go-service:latest "$projectRoot\go-service"
} -ArgumentList $acrName, $ProjectRoot

Write-Host "  - Starting load-generator build..."
$jobs += Start-Job -ScriptBlock {
    param($acrName, $projectRoot)
    az acr build --registry $acrName --image load-generator:latest "$projectRoot\load-generator"
} -ArgumentList $acrName, $ProjectRoot

Write-Host "Background builds started!"

# Get AKS credentials
Write-Host ""
Write-Host "Step 4b: Getting AKS credentials..." -ForegroundColor Green
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

# Wait for ACR builds to complete
Write-Host ""
Write-Host "Step 5: Waiting for container image builds to complete..." -ForegroundColor Green
Write-Host "This may take a few more minutes if not already finished..."

$jobs | Wait-Job | Out-Null

# Check if any builds failed
$failedJobs = $jobs | Where-Object { $_.State -eq 'Failed' }
if ($failedJobs) {
    Write-Host "Some builds failed:" -ForegroundColor Red
    $failedJobs | ForEach-Object {
        Write-Host "Job $($_.Id) failed" -ForegroundColor Red
        Receive-Job -Job $_ | Write-Host
    }
    $jobs | Remove-Job -Force
    exit 1
}

# Clean up jobs
$jobs | Remove-Job -Force

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
kubectl apply -f "$ProjectRoot\k8s\java-service.yaml"
kubectl apply -f "$ProjectRoot\k8s\go-service.yaml"

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

# Ensure we have just the ACR name without .azurecr.io suffix
$acrNameOnly = $acrName -replace '\.azurecr\.io$', ''

$sshPrivateKey = $SshKeyPath -replace '\.pub$', ''

# Copy vm-setup.sh to VM and execute
Write-Host "Copying setup script to VM..."
scp -i $sshPrivateKey -o StrictHostKeyChecking=no "$ScriptDir\vm-setup.sh" azureuser@${vmIp}:/tmp/vm-setup.sh

Write-Host "Running setup script on VM..."
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "chmod +x /tmp/vm-setup.sh && bash /tmp/vm-setup.sh '$acrNameOnly' '$acrPassword' '$OtelTracesEndpoint' '$OtelMetricsEndpoint' '$javaServiceUrl'"

# Deploy to VM
Write-Host ""
Write-Host "Step 8: Deploying .NET service to VM..." -ForegroundColor Green

# Update docker-compose on VM and restart - use separate commands to avoid line ending issues
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "docker login ${acrNameOnly}.azurecr.io -u $acrNameOnly -p '$acrPassword'"
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "cd /opt/otel-bugbash && sed -i 's|JAVA_SERVICE_URL=.*|JAVA_SERVICE_URL=${javaServiceUrl}|' docker-compose.yml"
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "cd /opt/otel-bugbash && docker compose pull"
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "sudo systemctl daemon-reload"
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "sudo systemctl enable otel-bugbash"
ssh -i $sshPrivateKey -o StrictHostKeyChecking=no azureuser@$vmIp "sudo systemctl restart otel-bugbash"

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
Write-Host "  ssh azureuser@$vmIp"
Write-Host "  Password: OtelBugBash2025!"
Write-Host ""
Write-Host "  (Or with key: ssh -i $sshPrivateKey azureuser@$vmIp)"
Write-Host ""
Write-Host "Run Load Test:" -ForegroundColor Yellow
Write-Host "  ssh azureuser@$vmIp"
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
