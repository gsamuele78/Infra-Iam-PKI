#!/bin/bash
set -e

# Wait for Step-CA to be ready
echo "Waiting for Step-CA to initialize..."
until curl -sk https://step-ca:9000/health | grep -q "ok"; do
    sleep 2
done
echo "Step-CA is up."

# Force patch call immediately after CA is reachable but before logic proceeds
# (Though CA needs restart to pick it up, this is a safety net)
if [ -f "/scripts/patch_ca_config.sh" ]; then
    echo "Running config patcher..."
    /bin/bash /scripts/patch_ca_config.sh || echo "Patch failed or not needed."
fi

echo "Checking file visibility..."
ls -la /home/step/certs/
if [ -f "/home/step/certs/root_ca.crt" ]; then
    echo "Root CA found at /home/step/certs/root_ca.crt"
else
    echo "ERROR: Root CA NOT found at /home/step/certs/root_ca.crt"
    exit 1
fi

echo "Checking password file..."
ls -la "$STEP_CA_PASSWORD_FILE"
if [ -r "$STEP_CA_PASSWORD_FILE" ]; then
    echo "Password file is readable."
    echo "Password length: $(wc -c < "$STEP_CA_PASSWORD_FILE")"
else
    echo "ERROR: Password file is NOT readable by user $(id -u)"
    exit 1
fi

# Set CA connection parameters as environment variables
export STEPPATH=/home/step
export STEP_CA_URL="https://step-ca:9000"

# Authenticate as admin ONCE at the start
echo "Authenticating as admin..."
step ca admin list --ca-url "$STEP_CA_URL" \
    --root /home/step/certs/root_ca.crt \
    --admin-subject="step" \
    --admin-provisioner="admin" \
    --password-file="$STEP_CA_PASSWORD_FILE" > /dev/null 2>&1 || {
    echo "Admin authentication failed. Attempting to bootstrap admin token..."
    # Generate an admin token for this session
    TOKEN=$(step ca token --admin \
        --admin-subject="step" \
        --admin-provisioner="admin" \
        --password-file="$STEP_CA_PASSWORD_FILE" \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt bootstrap 2>/dev/null || echo "")
    
    if [ -z "$TOKEN" ]; then
        echo "ERROR: Could not generate admin token"
        exit 1
    fi
    export STEP_CA_TOKEN="$TOKEN"
}

# Helper to add provisioner if missing
add_provisioner() {
    local name=$1
    local type=$2
    shift 2
    local args="$@"
    
    # Check if provisioner exists
    if step ca provisioner list \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt 2>/dev/null | grep -q "\"name\": \"$name\""; then
        echo "Provisioner '$name' already exists."
        return 0
    fi
    
    echo "Adding provisioner '$name' ($type)..."
    step ca provisioner add "$name" --type "$type" $args \
        --admin-subject="step" \
        --admin-provisioner="admin" \
        --password-file="$STEP_CA_PASSWORD_FILE" \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt
}

# SSH Provisioner Configuration
if [ "$ENABLE_SSH_PROVISIONER" = "true" ]; then
    echo "Configuring SSH Host Provisioners..."
    
    # A. SSH-POP (Proof of Possession) - Essential for RENEWAL of host certs
    if ! step ca provisioner list \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt 2>/dev/null | grep -q "\"type\": \"SSHPOP\""; then
        echo "Adding SSH-POP provisioner (for host renewal)..."
        step ca provisioner add "ssh-pop" --type "SSHPOP" \
            --admin-subject="step" \
            --admin-provisioner="admin" \
            --password-file="$STEP_CA_PASSWORD_FILE" \
            --ca-url "$STEP_CA_URL" \
            --root /home/step/certs/root_ca.crt
    else
        echo "SSH-POP provisioner already exists."
    fi

    # B. JWK Provisioner (Specific for SSH Hosts)
    if [ -n "$SSH_HOST_PROVISIONER_PASSWORD" ]; then
        echo "Adding dedicated JWK provisioner for SSH Initial Enrollment..."
        
        if ! step ca provisioner list \
            --ca-url "$STEP_CA_URL" \
            --root /home/step/certs/root_ca.crt 2>/dev/null | grep -q "\"name\": \"ssh-host-jwk\""; then
            
            # Create a password-protected JWK provisioner
            echo "$SSH_HOST_PROVISIONER_PASSWORD" > /tmp/host_jwk_pass
            
            # 1. Generate Keypair if it doesn't exist
            if [ ! -f "/home/step/secrets/ssh_host_jwk_key" ]; then
                echo "Generating JWK Keypair..."
                step crypto jwk create \
                    /home/step/certs/ssh_host_jwk.pub \
                    /home/step/secrets/ssh_host_jwk_key \
                    --password-file /tmp/host_jwk_pass \
                    --force
            fi

            # 2. Add Provisioner using the Public Key
            echo "Adding 'ssh-host-jwk' provisioner..."
            step ca provisioner add "ssh-host-jwk" --type "JWK" \
                --public-key /home/step/certs/ssh_host_jwk.pub \
                --admin-subject="step" \
                --admin-provisioner="admin" \
                --password-file="$STEP_CA_PASSWORD_FILE" \
                --ca-url "$STEP_CA_URL" \
                --root /home/step/certs/root_ca.crt
                
            rm -f /tmp/host_jwk_pass
        else
            echo "JWK provisioner 'ssh-host-jwk' already exists."
        fi
    fi
fi

# ACME Provisioner
if [ "$ENABLE_ACME" = "true" ]; then
    echo "Configuring ACME..."
    add_provisioner "acme" "ACME"
fi

# K8s Service Account Provisioner
if [ "$ENABLE_K8S_PROVISIONER" = "true" ]; then
    echo "Configuring K8s Service Account Provisioner..."
    K8S_KEY_FILE="/home/step/secrets/k8s_sa_pub.pem"
    
    if [ -f "$K8S_KEY_FILE" ]; then
        if ! step ca provisioner list \
            --ca-url "$STEP_CA_URL" \
            --root /home/step/certs/root_ca.crt 2>/dev/null | grep -q "\"type\": \"K8sSA\""; then
            echo "Adding K8sSA provisioner..."
            step ca provisioner add "k8s-sa" --type "K8sSA" \
                --public-key "$K8S_KEY_FILE" \
                --admin-subject="step" \
                --admin-provisioner="admin" \
                --password-file="$STEP_CA_PASSWORD_FILE" \
                --ca-url "$STEP_CA_URL" \
                --root /home/step/certs/root_ca.crt
        else
            echo "K8sSA provisioner already exists."
        fi
    else
        echo "Warning: ENABLE_K8S_PROVISIONER is true, but $K8S_KEY_FILE not found. Skipping K8sSA setup."
    fi
fi

# Final verification
echo ""
echo "=== Final Provisioner List ==="
step ca provisioner list \
    --ca-url "$STEP_CA_URL" \
    --root /home/step/certs/root_ca.crt 2>/dev/null | grep -E '"name"|"type"' | paste - - || echo "Could not list provisioners"

echo ""
echo "Initialization steps completed successfully."
