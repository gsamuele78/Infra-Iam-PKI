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

# Helper to add provisioner if missing
add_provisioner() {
    local name=$1
    local type=$2
    local args=$3
    
    # Use step-ca hostname for internal docker networking
    if step ca provisioner list --ca-url "https://step-ca:9000" --root /home/step/certs/root_ca.crt | grep -q "\"name\": \"$name\""; then
        echo "Provisioner '$name' already exists."
    else
        echo "Adding provisioner '$name' ($type)..."
        step ca provisioner add "$name" --type "$type" $args --admin-subject="step" --password-file="$STEP_CA_PASSWORD_FILE" --ca-url "https://step-ca:9000" --root /home/step/certs/root_ca.crt
    fi
}
# ...
if [ "$ENABLE_SSH_PROVISIONER" = "true" ]; then
    echo "Configuring SSH Host Provisioners..."
    
    # A. SSH-POP (Proof of Possession) - Essential for RENEWAL of host certs
    if ! step ca provisioner list --ca-url "https://step-ca:9000" --root /home/step/certs/root_ca.crt | grep -q "\"type\": \"SSHPOP\""; then
         echo "Adding SSH-POP provisioner (for host renewal)..."
         # This uses the CA's existing SSH host key to verify renewal requests signed by current valid certs.
         step ca provisioner add "ssh-pop" --type "SSHPOP" --admin-subject="step" --password-file="$STEP_CA_PASSWORD_FILE" --ca-url "https://step-ca:9000" --root /home/step/certs/root_ca.crt
    else
         echo "SSH-POP provisioner already exists."
    fi

    # B. JWK Provisioner (Specific for SSH Hosts)
    # While the default provisioner often works, dedicated one is cleaner for host automation.
    if [ -n "$SSH_HOST_PROVISIONER_PASSWORD" ]; then
         echo "Adding dedicated JWK provisioner for SSH Initial Enrollment..."
         if ! step ca provisioner list --ca-url "https://step-ca:9000" --root /home/step/certs/root_ca.crt | grep -q "\"name\": \"ssh-host-jwk\""; then
             # Create a password-protected JWK provisioner specifically for bootstrapping hosts
             echo "$SSH_HOST_PROVISIONER_PASSWORD" > /tmp/host_jwk_pass
             
             # 1. Generate Keypair explicitly so we can persist the private key
             if [ ! -f "/home/step/secrets/ssh_host_jwk_key" ]; then
                echo "Generating JWK Keypair..."
                step crypto jwk create /home/step/certs/ssh_host_jwk.pub /home/step/secrets/ssh_host_jwk_key \
                    --password-file /tmp/host_jwk_pass \
                    --force
             fi

             # 2. Add Provisioner using the Public Key
             # --create=false is implied when providing keys, but we can be explicit if needed.
             # We use --public-key to link it.
             echo "Adding 'ssh-host-jwk' provisioner..."
             step ca provisioner add "ssh-host-jwk" --type "JWK" --public-key /home/step/certs/ssh_host_jwk.pub \
                 --admin-subject="step" --password-file="$STEP_CA_PASSWORD_FILE" \
                 --ca-url "https://step-ca:9000" --root /home/step/certs/root_ca.crt
                 
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
