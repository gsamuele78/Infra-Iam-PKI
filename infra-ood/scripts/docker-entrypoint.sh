#!/bin/bash
set -e

echo "--- Open OnDemand Container Entrypoint ---"

# Trust the PKI Root CA if provided
if [ -f /certs/root_ca.crt ]; then
    echo "Trusting PKI Root CA..."
    cp /certs/root_ca.crt /usr/local/share/ca-certificates/step-ca.crt
    update-ca-certificates
fi

# Generate ood_portal.conf from ood_portal.yml using the OOD tool
if [ -f /etc/ood/config/ood_portal.yml ]; then
    echo "Resolving environment variables in ood_portal.yml..."
    # Substitute variables to a temporary file, then overwrite
    sed -e "s|%{env:OIDC_URI}|${OIDC_URI}|g" \
        -e "s|%{env:OIDC_CLIENT_ID}|${OIDC_CLIENT_ID}|g" \
        -e "s|%{env:OIDC_CLIENT_SECRET}|${OIDC_CLIENT_SECRET}|g" \
        /etc/ood/config/ood_portal.yml > /tmp/ood_portal.yml.rendered
    
    echo "Generating ood_portal.conf from ood_portal.yml..."
    /opt/ood/ood-portal-generator/sbin/update_ood_portal --config /tmp/ood_portal.yml.rendered
fi

# Ensure dirs exist
mkdir -p /var/www/ood/public

echo "Starting Apache2..."
exec "$@"
