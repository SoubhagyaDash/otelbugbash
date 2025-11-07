# Prerequisites and Environment Setup

Complete guide for setting up your environment to deploy the OpenTelemetry Bug Bash application.

## Required Software

### 1. Azure CLI ✅

**Why needed:** Deploy infrastructure, manage resources, authenticate to Azure

**Install:**

**Windows (PowerShell):**
```powershell
winget install Microsoft.AzureCLI
```

**macOS:**
```bash
brew install azure-cli
```

**Linux:**
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**Verify:**
```bash
az --version
# Should show version 2.50.0 or higher
```

---

### 2. kubectl ✅

**Why needed:** Deploy and manage Kubernetes services on AKS

**Install:**

**Windows (PowerShell):**
```powershell
winget install Kubernetes.kubectl
```

**macOS:**
```bash
brew install kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**Verify:**
```bash
kubectl version --client
# Should show version 1.28.0 or higher
```

---

### 3. SSH Client ✅

**Why needed:** Connect to VM for troubleshooting and manual operations

**Check if installed:**
```bash
ssh -V
# Should show OpenSSH version
```

**If not installed:**

**Windows:** Included in Windows 10/11 by default
```powershell
# Enable if needed
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

**macOS/Linux:** Pre-installed

---

### 4. Git ✅

**Why needed:** Clone the repository

**Install:**

**Windows:**
```powershell
winget install Git.Git
```

**macOS:**
```bash
brew install git
```

**Linux:**
```bash
sudo apt-get install git  # Debian/Ubuntu
sudo yum install git      # RHEL/CentOS
```

**Verify:**
```bash
git --version
```

---

## Optional Software

### 5. Bicep CLI (Optional)

**Why needed:** Only if you want to modify infrastructure templates

**Note:** Azure CLI includes Bicep automatically in recent versions

**Verify:**
```bash
az bicep version
```

**Install separately (if needed):**
```bash
az bicep install
```

---

### 6. jq (Optional)

**Why needed:** JSON parsing in scripts (scripts have fallbacks if not installed)

**Install:**

**Windows:**
```powershell
winget install jqlang.jq
```

**macOS:**
```bash
brew install jq
```

**Linux:**
```bash
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # RHEL/CentOS
```

---

## Azure Requirements

### 1. Azure Subscription ✅

**What you need:**
- Active Azure subscription
- **Contributor** or **Owner** role on the subscription or resource group
- No spending limits that would prevent VM/AKS creation

**Check your access:**
```bash
# Login
az login

# List subscriptions
az account list --output table

# Set active subscription
az account set --subscription "<subscription-id>"

# Verify access
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

### 2. Resource Quotas ✅

Ensure you have sufficient quota in your Azure region:

| Resource | Required | Typical Default |
|----------|----------|-----------------|
| vCPUs | 8+ cores | 10-20 cores |
| Standard_D2s_v3 VMs | 1 VM | Usually available |
| AKS Clusters | 1 cluster | Usually available |
| Public IPs | 2-3 IPs | Usually available |
| Container Registries | 1 ACR | Usually available |

**Check quota:**
```bash
az vm list-usage --location eastus --output table
```

### 3. Service Principal / Managed Identity (Not Required)

**Note:** The deployment uses your Azure CLI authentication - no need to create service principals!

---

## SSH Key Setup

### Generate SSH Key Pair ✅

**Required for:** VM access and deployment

**Generate key:**

**Linux/macOS:**
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/otelbugbash_rsa -N ""
```

**Windows PowerShell:**
```powershell
ssh-keygen -t rsa -b 4096 -f $env:USERPROFILE\.ssh\otelbugbash_rsa -N ""
```

> **Important:** Use `-N ""` (empty string with no quotes) for a passwordless key. This is required for automated deployment.

**Verify:**
```bash
# Should see two files:
ls -la ~/.ssh/otelbugbash_rsa*

# ~/.ssh/otelbugbash_rsa      (private key - keep secret!)
# ~/.ssh/otelbugbash_rsa.pub  (public key - used in deployment)
```

**Permissions (Linux/macOS):**
```bash
chmod 600 ~/.ssh/otelbugbash_rsa
chmod 644 ~/.ssh/otelbugbash_rsa.pub
```

---

## Network Requirements

### Firewall / Proxy

If you're behind a corporate firewall, ensure these are accessible:

**Azure Services:**
- `*.azure.com` - Azure Management
- `*.azurecr.io` - Azure Container Registry
- `*.blob.core.windows.net` - Azure Storage

**External Services:**
- `github.com` - Repository cloning
- `packages.microsoft.com` - .NET packages
- `maven.apache.org` - Java packages
- `proxy.golang.org` - Go modules

**Ports:**
- 443 (HTTPS) - All Azure management
- 22 (SSH) - VM access
- 5000 (HTTP) - .NET service endpoint (from your machine)

---

## Environment Validation

### Quick Validation Script

Run this to verify all prerequisites:

```bash
#!/bin/bash

echo "=== Environment Validation ==="
echo ""

# Check Azure CLI
if command -v az &> /dev/null; then
    echo "✅ Azure CLI: $(az --version | head -n 1)"
else
    echo "❌ Azure CLI: NOT INSTALLED"
fi

# Check kubectl
if command -v kubectl &> /dev/null; then
    echo "✅ kubectl: $(kubectl version --client --short 2>/dev/null)"
else
    echo "❌ kubectl: NOT INSTALLED"
fi

# Check SSH
if command -v ssh &> /dev/null; then
    echo "✅ SSH: $(ssh -V 2>&1 | head -n 1)"
else
    echo "❌ SSH: NOT INSTALLED"
fi

# Check Git
if command -v git &> /dev/null; then
    echo "✅ Git: $(git --version)"
else
    echo "❌ Git: NOT INSTALLED"
fi

# Check Azure login
if az account show &> /dev/null; then
    echo "✅ Azure Login: $(az account show --query name -o tsv)"
else
    echo "❌ Azure Login: NOT LOGGED IN"
fi

# Check SSH key
if [ -f ~/.ssh/otelbugbash_rsa.pub ]; then
    echo "✅ SSH Key: Found at ~/.ssh/otelbugbash_rsa.pub"
else
    echo "⚠️  SSH Key: Not found (run: ssh-keygen -t rsa -b 4096 -f ~/.ssh/otelbugbash_rsa)"
fi

echo ""
echo "=== Validation Complete ==="
```

Save as `check-prerequisites.sh` and run:
```bash
chmod +x check-prerequisites.sh
./check-prerequisites.sh
```

---

## NOT Required

You **DO NOT** need to install:

- ❌ **Docker** - All builds happen in Azure ACR
- ❌ **.NET SDK** - Not needed locally (ACR builds .NET service)
- ❌ **Java JDK** - Not needed locally (ACR builds Java service)
- ❌ **Go** - Not needed locally (ACR builds Go services)
- ❌ **Node.js** - Not used in this project
- ❌ **Terraform** - We use Bicep instead
- ❌ **Helm** - We use kubectl with raw YAML

Everything is built **in the cloud** via Azure Container Registry!

---

## Platform-Specific Notes

### Windows

**PowerShell vs Command Prompt:**
- Use **PowerShell** (recommended) or **Windows Terminal**
- Scripts are written for bash, but Azure CLI commands work in PowerShell

**WSL (Windows Subsystem for Linux):**
- You can use WSL for a native Linux experience
- Install Azure CLI and kubectl inside WSL
- SSH keys work seamlessly

**Git Bash:**
- Alternative to WSL
- Comes with Git for Windows
- Provides bash environment on Windows

### macOS

**Homebrew:**
- Easiest way to install most prerequisites
- Install Homebrew first: https://brew.sh

**Rosetta 2 (Apple Silicon):**
- All tools support ARM64 natively
- No additional configuration needed

### Linux

**Package Managers:**
- Ubuntu/Debian: `apt-get`
- RHEL/CentOS: `yum` or `dnf`
- Arch: `pacman`

**Snap (alternative):**
```bash
sudo snap install kubectl --classic
sudo snap install azure-cli --classic
```

---

## Estimated Time

| Task | Time |
|------|------|
| Install prerequisites | 15-30 minutes |
| Azure login & setup | 5 minutes |
| SSH key generation | 2 minutes |
| Repository clone | 1 minute |
| **Total setup time** | **~30-45 minutes** |

| Deployment Phase | Time |
|-----------------|------|
| Infrastructure deployment | 10-15 minutes |
| Container builds (in ACR) | 5-10 minutes |
| Service deployment | 5 minutes |
| **Total deployment time** | **~20-30 minutes** |

---

## Estimated Costs

Running this environment in Azure (East US region):

| Resource | Size | Hourly Cost | Daily Cost |
|----------|------|-------------|------------|
| VM (Standard_D2s_v3) | 2 vCPU, 8 GB RAM | ~$0.10 | ~$2.40 |
| AKS (2 nodes, Standard_D2s_v3) | 4 vCPU, 16 GB RAM | ~$0.20 | ~$4.80 |
| ACR (Basic tier) | Container registry | ~$0.007 | ~$0.17 |
| Load Balancer | Standard | ~$0.025 | ~$0.60 |
| Public IPs | 2-3 IPs | ~$0.015 | ~$0.36 |
| **Total Estimated** | | **~$0.35/hr** | **~$8.33/day** |

**Note:** Delete resources immediately after bug bash to avoid ongoing charges!

---

## Troubleshooting Setup Issues

### Azure CLI Login Issues

```bash
# Clear cached credentials
az account clear

# Re-login with device code
az login --use-device-code

# Or use specific tenant
az login --tenant <tenant-id>
```

### SSH Key Permission Issues (Linux/macOS)

```bash
# Fix permissions
chmod 600 ~/.ssh/otelbugbash_rsa
chmod 644 ~/.ssh/otelbugbash_rsa.pub
chmod 700 ~/.ssh
```

### kubectl Not Found After Install

```bash
# Add to PATH (Linux/macOS)
export PATH=$PATH:/usr/local/bin

# Or reload shell
source ~/.bashrc  # or ~/.zshrc
```

### Azure Quota Exceeded

```bash
# Request quota increase
# Go to Azure Portal → Subscriptions → Usage + quotas
# Or contact Azure Support
```

---

## Ready to Deploy?

Once all prerequisites are met:

1. ✅ Azure CLI installed and logged in
2. ✅ kubectl installed
3. ✅ SSH client available
4. ✅ Git installed
5. ✅ SSH key pair generated
6. ✅ Azure subscription with sufficient quota

**You're ready to deploy!**

```bash
# Clone repository
git clone https://github.com/YourOrg/OtelBugBash.git
cd OtelBugBash

# Run deployment
cd scripts
./deploy-all.sh otel-bugbash-rg eastus ~/.ssh/otelbugbash_rsa.pub \
  http://your-collector:4319 \
  http://your-collector:4317
```

See [QUICKSTART.md](./QUICKSTART.md) or [BUGBASH_INSTRUCTIONS.md](./BUGBASH_INSTRUCTIONS.md) for detailed deployment steps.
