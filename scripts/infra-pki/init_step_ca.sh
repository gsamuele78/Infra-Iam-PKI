#!/bin/bash
set -e

# Wait for Step-CA to be ready
echo "Waiting for Step-CA to initialize..."
until curl -sk https://step-ca:9000/health | grep -q "ok"; do
    sleep 2
done
echo "Step-CA is up."

# Helper to add provisioner if missing
add_provisioner() {
    local name=$1
    local type=$2
    local args=$3
    
    if step ca provisioner list | grep -q "\"name\": \"$name\""; then
        echo "Provisioner '$name' already exists."
    else
        echo "Adding provisioner '$name' ($type)..."
        step ca provisioner add "$name" --type "$type" $args --admin-subject="step" --password-file="$STEP_CA_PASSWORD_FILE"
    fi
}

# Helper to read secret from file or env
read_secret() {
    local env_var_name=$1
    local file_var_name=$2
    local val=${!env_var_name}
    local file_val=${!file_var_name}
    
    if [ -n "$file_val" ] && [ -f "$file_val" ]; then
        cat "$file_val"
    else
        echo "$val"
    fi
}

OIDC_CLIENT_SECRET=$(read_secret OIDC_CLIENT_SECRET OIDC_CLIENT_SECRET_FILE)
SSH_HOST_PROVISIONER_PASSWORD=$(read_secret SSH_HOST_PROVISIONER_PASSWORD SSH_HOST_PROVISIONER_PASSWORD_FILE)

# 1. OIDC Provisioner (For SSH User Certs via SSO)
if [ -n "$OIDC_CLIENT_ID" ] && [ -n "$OIDC_CLIENT_SECRET" ]; then
    echo "Configuring OIDC..."
    # OIDC provisioners naturally support SSH user certs if the functionality is enabled in the client.
    # No special flag needed on the CA side except standard OIDC config.
    add_provisioner "$OIDC_NAME" "OIDC" "--client-id=$OIDC_CLIENT_ID --client-secret=$OIDC_CLIENT_SECRET --configuration-endpoint=$OIDC_ENDPOINT --domain=$OIDC_DOMAIN"
fi

# 2. SSH Host Support
# Best Practice: 
# - Use a JWK provisioner (or OIDC) to sign INITIAL certificates (step ca certificate --provisioner ...).
# - Use 'ssh-pop' provisioner to RENEW certificates (step ca renew ...).

if [ "$ENABLE_SSH_PROVISIONER" = "true" ]; then
    echo "Configuring SSH Host Provisioners..."
    
    # A. SSH-POP (Proof of Possession) - Essential for RENEWAL of host certs
    if ! step ca provisioner list | grep -q "\"type\": \"SSH\""; then
         echo "Adding SSH-POP provisioner (for host renewal)..."
         # This uses the CA's existing SSH host key to verify renewal requests signed by current valid certs.
         step ca provisioner add "ssh-pop" --type "ssh" --admin-subject="step" --password-file="$STEP_CA_PASSWORD_FILE"
    else
         echo "SSH-POP provisioner already exists."
    fi

    # B. JWK Provisioner (Specific for SSH Hosts)
    # While the default provisioner often works, dedicated one is cleaner for host automation.
    if [ -n "$SSH_HOST_PROVISIONER_PASSWORD" ]; then
         echo "Adding dedicated JWK provisioner for SSH Initial Enrollment..."
         if ! step ca provisioner list | grep -q "\"name\": \"ssh-host-jwk\""; then
             # Create a password-protected JWK provisioner specifically for bootstrapping hosts
             echo "$SSH_HOST_PROVISIONER_PASSWORD" > /tmp/host_jwk_pass
             step ca provisioner add "ssh-host-jwk" --type "JWK" --password-file-from-stdin < /tmp/host_jwk_pass --admin-subject="step" --password-file="$STEP_CA_PASSWORD_FILE"
             rm /tmp/host_jwk_pass
         else
             echo "JWK provisioner 'ssh-host-jwk' already exists."
         fi
    fi
fi

# 3. ACME Provisioner
if [ "$ENABLE_ACME" = "true" ]; then
    echo "Configuring ACME..."
    add_provisioner "acme" "ACME" ""
fi

# 4. K8s Service Account Provisioner (Future Support)
# Enables workload identity for Kubernetes clusters (cert-manager / step-issuer)
if [ "$ENABLE_K8S_PROVISIONER" = "true" ]; then
    echo "Configuring K8s Service Account Provisioner..."
    # This requires the public signing key of the K8s Service Account Issuer.
    # We will look for it in a mounted file or env var.
    # Usage: step ca provisioner add k8s-sa --type K8sSA --public-key ...
    
    # Placeholder: Check if user provided the key file
    K8S_KEY_FILE="/home/step/secrets/k8s_sa_pub.pem"
    
    if [ -f "$K8S_KEY_FILE" ]; then
         if ! step ca provisioner list | grep -q "\"type\": \"K8sSA\""; then
             echo "Adding K8sSA provisioner..."
             step ca provisioner add "k8s-sa" --type "K8sSA" --public-key "$K8S_KEY_FILE" --admin-subject="step" --password-file="$STEP_CA_PASSWORD_FILE"
         else
             echo "K8sSA provisioner already exists."
         fi
    else
         echo "Warning: ENABLE_K8S_PROVISIONER is true, but $K8S_KEY_FILE not found. Skipping K8sSA setup."
    fi
fi

echo "Initialization steps completed."
