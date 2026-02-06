#!/bin/bash
# verify_pki.sh - Quick verification of PKI status

echo "======================================"
echo "   PKI Infrastructure Verification"
echo "======================================"
echo ""

cd /opt/docker/Infra-Iam-PKI/infra-pki || exit

echo "1. Container Status:"
echo "--------------------"
docker compose ps
echo ""

echo "2. CA Health Check:"
echo "--------------------"
curl -k https://localhost:9000/health
echo ""
echo ""

echo "3. Root CA Fingerprint:"
echo "--------------------"
cat step_data/fingerprint
echo ""

echo "4. Provisioners List:"
echo "--------------------"
docker compose exec step-ca step ca provisioner list | grep -E '"name"|"type"' | paste - - | sed 's/,$//'
echo ""

echo "5. Configurator Status:"
echo "--------------------"
docker compose ps configurator
echo ""

echo "======================================"
echo "   Verification Complete"
echo "======================================"