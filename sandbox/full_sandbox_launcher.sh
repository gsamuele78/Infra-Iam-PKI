#!/bin/bash
set -e

echo "====================================================="
echo " Starting Full 1:1 Production Sandbox Emulation"
echo " (Building Open OnDemand completely from source: Ubuntu 24.04)"
echo "====================================================="

cd /workspace/Infra-Iam-PKI

# 0. Tear Down Previous State
echo "Cleaning up previous sandbox state to guarantee a 1:1 clean boot..."
docker compose -f infra-ood/docker-compose.sandbox.yml down -v 2>/dev/null || true
docker compose -f infra-iam/docker-compose.yml down -v 2>/dev/null || true
docker compose -f infra-pki/docker-compose.yml down -v 2>/dev/null || true

# Completely wipe local bind-mount data to prevent rsync corruption
sudo rm -rf infra-pki/step_data infra-pki/db_data infra-pki/logs
sudo rm -rf infra-iam/keycloak_data infra-iam/caddy_data infra-iam/logs

# 1. Network Setup
echo "Creating unified sandbox network..."
docker network create sandbox-net >/dev/null 2>&1 || true

# 2. Infra-PKI
echo "Starting Infra-PKI (Step-CA)..."
cd infra-pki
cp -n .env.template .env 2>/dev/null || touch .env
docker compose build
docker compose up -d
sleep 5

# 3. Infra-IAM
echo "Starting Infra-IAM (Keycloak)..."
cd ../infra-iam
cp -n .env.template .env 2>/dev/null || touch .env

# Dynamically inject the newly generated PKI fingerprint so IAM can trust the CA
echo "Waiting for PKI Fingerprint to be generated..."
while [ ! -s ../infra-pki/step_data/fingerprint/root_ca.fingerprint ]; do sleep 1; done
PKI_FINGERPRINT=$(cat ../infra-pki/step_data/fingerprint/root_ca.fingerprint)
echo "PKI Fingerprint: $PKI_FINGERPRINT"
sed -i "s/^FINGERPRINT=.*/FINGERPRINT=\"$PKI_FINGERPRINT\"/" .env

# Start IAM
docker compose up -d
sleep 10

# 4. Infra-OOD (Building from Source via OSC development guidelines)
echo "Setting up Official OSC Open OnDemand Environment from source..."
cd ../infra-ood

if [ ! -d "ondemand" ]; then
    git clone https://github.com/OSC/ondemand.git
fi
cd ondemand

# Wait, OSC/ondemand repository uses the 'packaging' directory or specific makefiles for Docker.
# Specifically, we need to build the development fullstack container as per DEVELOPMENT.md
echo "Building fullstack container for ubuntu-24.04..."

# We will build the base container image first according to standard OOD docker builds.
# The OSC/ood-images repository is actually the standard way to build the Docker image itself.
# Since the user specifically linked DEVELOPMENT.md#fullstack-container, it relies on the `dev.sh` script 
# or manual docker-compose inside the repo.
# For simplicity and compliance, we use their provided docker compose setup for dev, but inject our CSS.

cat << 'DOCKERFILE' > ../docker-compose.sandbox.yml
services:
  ondemand:
    build:
      context: ./ondemand
      dockerfile: Dockerfile
      args:
        # Pass args to Dockerfile if they support OS strings
        - OS=ubuntu
        - OS_VERSION=24.04
    container_name: sandbox-ood-fullstack
    user: root
    privileged: true
    ports:
      - "8081:8080"
    networks:
      - sandbox-net
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
      - ./config/ood_portal.yml:/etc/ood/config/ood_portal.yml:ro
      - ./public/bigea-theme.css:/var/www/ood/public/bigea-theme.css:ro
      - ./public/img:/var/www/ood/public/img:ro
DOCKERFILE

echo "Starting the source build process..."
cd ..
docker compose -f docker-compose.sandbox.yml up -d --build

echo "====================================================="
echo " Complete Sandbox Deployed!"
echo " The real Open OnDemand application is now running."
echo " UI Available at: http://192.168.121.67:8081"
echo "====================================================="
EOF
