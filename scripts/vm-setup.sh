#!/bin/bash
set -e

echo "=== OpenTelemetry Bug Bash VM Setup Script ==="
echo "Starting setup at $(date)"

ACR_NAME="${1}"
ACR_PASSWORD="${2}"
OTEL_TRACES_ENDPOINT="${3:-http://localhost:4319}"
OTEL_METRICS_ENDPOINT="${4:-http://localhost:4317}"
JAVA_SERVICE_URL="${5:-http://java-service:8080}"

echo "ACR Name: $ACR_NAME"
echo "OTLP Traces/Logs Endpoint: $OTEL_TRACES_ENDPOINT"
echo "OTLP Metrics Endpoint: $OTEL_METRICS_ENDPOINT"
echo "Java Service URL: $JAVA_SERVICE_URL"

# Update system
echo "Updating system packages..."
sudo apt-get update -qq > /dev/null
sudo apt-get upgrade -y -qq > /dev/null
echo "System packages updated successfully"

# Install Docker using official apt repository (more reliable than get.docker.com)
echo "Installing Docker..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found, installing from official repository..."
    
    # Install prerequisites
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    echo "Docker installed successfully"
else
    echo "Docker already installed: $(docker --version)"
fi

# Verify Docker Compose plugin is available
echo "Verifying Docker Compose..."
if docker compose version &> /dev/null; then
    echo "Docker Compose plugin: $(docker compose version)"
else
    echo "Warning: Docker Compose plugin not found, installing standalone..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Login to ACR
echo "Logging in to Azure Container Registry..."
docker login "${ACR_NAME}.azurecr.io" -u "$ACR_NAME" -p "$ACR_PASSWORD"

# Create directories
echo "Creating application directories..."
sudo mkdir -p /opt/otel-bugbash
sudo chown -R $USER:$USER /opt/otel-bugbash
cd /opt/otel-bugbash

# Create docker-compose file
echo "Creating docker-compose configuration..."
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  dotnet-service:
    image: ${ACR_NAME}.azurecr.io/dotnet-service:latest
    container_name: dotnet-service
    restart: always
    network_mode: "host"
    environment:
      - ASPNETCORE_URLS=http://+:5000
      - OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=${OTEL_TRACES_ENDPOINT}
      - OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=${OTEL_METRICS_ENDPOINT}
      - JAVA_SERVICE_URL=${JAVA_SERVICE_URL}
      - OTEL_RESOURCE_ATTRIBUTES

  load-generator:
    image: ${ACR_NAME}.azurecr.io/load-generator:latest
    container_name: load-generator
    restart: "no"
    network_mode: "host"
    volumes:
      - ./reports:/reports
    profiles:
      - tools
EOF

# Create systemd service for docker-compose
# Create systemd service for docker compose
echo "Creating systemd service..."
sudo tee /etc/systemd/system/otel-bugbash.service > /dev/null <<EOF
[Unit]
Description=OpenTelemetry Bug Bash .NET Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/otel-bugbash
ExecStart=/usr/bin/docker compose up -d dotnet-service
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose pull && /usr/bin/docker compose up -d
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create helper scripts
echo "Creating helper scripts..."

# Script to run load tests
cat > /opt/otel-bugbash/run-load-test.sh <<'EOF'
#!/bin/bash
DURATION="${1:-10m}"
RATE="${2:-10}"
REPORT_FILE="${3:-/reports/load-test-$(date +%Y%m%d-%H%M%S).json}"

echo "Running load test..."
echo "  Duration: $DURATION"
echo "  Rate: $RATE req/sec"
echo "  Report: $REPORT_FILE"

docker compose run --rm load-generator \
  --url http://localhost:5000/api/process \
  --duration "$DURATION" \
  --rate "$RATE" \
  --report-file "$REPORT_FILE"

echo "Load test complete. Report saved to: $REPORT_FILE"
EOF
chmod +x /opt/otel-bugbash/run-load-test.sh

# Script to view logs
cat > /opt/otel-bugbash/view-logs.sh <<'EOF'
#!/bin/bash
docker compose logs -f dotnet-service
EOF
chmod +x /opt/otel-bugbash/view-logs.sh

# Script to update services
cat > /opt/otel-bugbash/update-services.sh <<'EOF'
#!/bin/bash
echo "Pulling latest images..."
docker compose pull
echo "Restarting services..."
docker compose up -d
echo "Services updated!"
EOF
chmod +x /opt/otel-bugbash/update-services.sh

# Create reports directory
mkdir -p /opt/otel-bugbash/reports

echo "Setup script completed at $(date)"
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Services will be managed via systemd:"
echo "  Start:   sudo systemctl start otel-bugbash"
echo "  Stop:    sudo systemctl stop otel-bugbash"
echo "  Status:  sudo systemctl status otel-bugbash"
echo "  Logs:    cd /opt/otel-bugbash && docker compose logs -f"
echo ""
echo "Helper scripts in /opt/otel-bugbash/:"
echo "  ./run-load-test.sh [duration] [rate] [report-file]"
echo "  ./view-logs.sh"
echo "  ./update-services.sh"
echo ""
echo "Note: Images need to be pulled from ACR before starting services"
