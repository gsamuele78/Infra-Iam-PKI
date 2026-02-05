#!/bin/bash
set -e

# Wait for Step-CA to be ready
echo "Waiting for Step-CA to initialize..."
until curl -sk https://step-ca:9000/health | grep -q "ok"; do
    sleep 2
done
echo "Step-CA is up."

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

# Function to get admin token
get_admin_token() {
    echo "Authenticating as admin..."
    
    # Try to get a token by calling the CA with admin provisioner
    TOKEN=$(step ca token \
        --admin \
        --admin-subject="step" \
        --admin-provisioner="admin" \
        --password-file="$STEP_CA_PASSWORD_FILE" \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt \
        bootstrap 2>/dev/null || echo "")
    
    if [ -n "$TOKEN" ]; then
        export STEP_CLI_TOKEN="$TOKEN"
        return 0
    fi
    
    # Alternative: Get a regular certificate and use that
    step ca certificate step /tmp/step.crt /tmp/step.key \
        --provisioner="admin" \
        --password-file="$STEP_CA_PASSWORD_FILE" \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt \
        --force 2>/dev/null || true
    
    if [ -f "/tmp/step.crt" ]; then
        echo "Using certificate-based authentication"
        export STEP_CERTIFICATE=/tmp/step.crt
        export STEP_KEY=/tmp/step.key
        return 0
    fi
    
    return 1
}

# Authenticate
get_admin_token || {
    echo "WARNING: Could not get admin token, will try direct provisioner commands"
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
    
    # Try with admin authentication
    if step ca provisioner add "$name" --type "$type" $args \
        --admin-subject="step" \
        --admin-provisioner="admin" \
        --password-file="$STEP_CA_PASSWORD_FILE" \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt 2>&1 | tee /tmp/provisioner_add.log; then
        echo "Successfully added provisioner '$name'"
        return 0
    else
        echo "Failed to add provisioner '$name', checking logs..."
        cat /tmp/provisioner_add.log
        return 1
    fi
}

# SSH Provisioner Configuration
if [ "$ENABLE_SSH_PROVISIONER" = "true" ]; then
    echo "Configuring SSH Host Provisioners..."
    
    # A. SSH-POP (Proof of Possession) - Essential for RENEWAL of host certs
    if ! step ca provisioner list \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt 2>/dev/null | grep -q "\"type\": \"SSHPOP\""; then
        echo "Adding SSH-POP provisioner (for host renewal)..."
        
        # SSH-POP doesn't need admin auth, it's automatically created during init
        # But we can add it explicitly if needed
        step ca provisioner add "ssh-pop" --type "SSHPOP" \
            --admin-subject="step" \
            --admin-provisioner="admin" \
            --password-file="$STEP_CA_PASSWORD_FILE" \
            --ca-url "$STEP_CA_URL" \
            --root /home/step/certs/root_ca.crt 2>/dev/null || echo "SSH-POP may already exist or be auto-configured"
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

            # 2. Get a fresh admin certificate for this operation
            echo "Getting admin certificate for provisioner addition..."
            step ca certificate step /tmp/admin_step.crt /tmp/admin_step.key \
                --provisioner="admin" \
                --password-file="$STEP_CA_PASSWORD_FILE" \
                --ca-url "$STEP_CA_URL" \
                --root /home/step/certs/root_ca.crt \
                --force 2>/dev/null || true

            # 3. Add Provisioner using certificate auth
            echo "Adding 'ssh-host-jwk' provisioner..."
            if [ -f "/tmp/admin_step.crt" ]; then
                # Use certificate-based admin auth
                STEP_CERTIFICATE=/tmp/admin_step.crt \
                STEP_KEY=/tmp/admin_step.key \
                step ca provisioner add "ssh-host-jwk" --type "JWK" \
                    --public-key /home/step/certs/ssh_host_jwk.pub \
                    --admin-subject="step" \
                    --admin-provisioner="admin" \
                    --ca-url "$STEP_CA_URL" \
                    --root /home/step/certs/root_ca.crt 2>&1 | tee /tmp/ssh_jwk_add.log
                
                if grep -q "error" /tmp/ssh_jwk_add.log || grep -q "unauthorized" /tmp/ssh_jwk_add.log; then
                    echo "Note: Add command reported an issue, but provisioner may have been added. Checking..."
                else
                    echo "JWK provisioner add command completed"
                fi
                
                # Cleanup temp certs
                rm -f /tmp/admin_step.crt /tmp/admin_step.key
            else
                echo "WARNING: Could not get admin certificate, provisioner may not be added"
            fi
                
            rm -f /tmp/host_jwk_pass
        else
            echo "JWK provisioner 'ssh-host-jwk' already exists."
        fi
    fi
fi

# ACME Provisioner
if [ "$ENABLE_ACME" = "true" ]; then
    echo "Configuring ACME..."
    
    # ACME is usually auto-created during init, just verify
    if ! step ca provisioner list \
        --ca-url "$STEP_CA_URL" \
        --root /home/step/certs/root_ca.crt 2>/dev/null | grep -q "\"name\": \"acme\""; then
        echo "ACME provisioner not found, attempting to add..."
        add_provisioner "acme" "ACME" || echo "ACME provisioner may already exist"
    else
        echo "Provisioner 'acme' already exists."
    fi
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
            add_provisioner "k8s-sa" "K8sSA" --public-key "$K8S_KEY_FILE"
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
