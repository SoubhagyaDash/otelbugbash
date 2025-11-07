#!/bin/bash
set -e

echo "Checking Docker..."
docker --version

echo "Logging into ACR..."
echo "${ACR_PASSWORD}" | docker login ${ACR_NAME}.azurecr.io -u ${ACR_NAME} --password-stdin

echo "Pulling .NET service image..."
docker pull ${ACR_NAME}.azurecr.io/dotnet-service:latest

echo "Starting .NET service..."
docker rm -f dotnet-service 2>/dev/null || true
docker run -d -p 5000:5000 --name dotnet-service \
  -e JAVA_SERVICE_URL=${JAVA_SERVICE_URL} \
  ${ACR_NAME}.azurecr.io/dotnet-service:latest

echo "Checking container status..."
docker ps | grep dotnet-service

echo "Done!"
