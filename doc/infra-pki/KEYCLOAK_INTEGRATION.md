# Keycloak (Infra-IAM) Integration with Step-CA

This guide explains how to secure Keycloak using certificates issued by your internal **Infra-PKI** (Step-CA).

## Architecture

- **PKI Host**: Runs `infra-pki` (Step-CA) at e.g., `172.30.119.221`.
- **IAM Host**: Runs `infra-iam` (Keycloak) at e.g., `172.30.119.223`.

The integration uses a **One-Time Token (OTT)** generated on the PKI Host to enroll the IAM Host securely.

## Workflow

### 1. On PKI Host: Generate Token

Login to the server running `infra-pki`.
Run the token generation script:

```bash
cd /opt/docker/Infra-Iam-PKI/
sudo scripts/infra-pki/generate_token.sh
```

- **Hostname**: `keycloak.internal` (or your actual IAM FQDN)
- **Copy** the generated token string.

### 2. On IAM Host: Deploy & Enroll

Login to the server running `infra-iam`.
Run the deployment script:

```bash
cd /opt/docker/Infra-Iam-PKI/
sudo scripts/infra-iam/deploy_iam.sh
```

- When prompted **"Enter Step-CA Token"**, paste the token from Step 1.
- The script will pass this token to the `iam-renewer` container.
- The container will automatically:
    1. Contact Step-CA (`CA_URL` from `.env`).
    2. Authenticate with the Token.
    3. Download `keycloak.crt` and `keycloak.key`.
    4. Start Keycloak.

## Automatic Renewal

After initial enrollment, the certificate itself is used for authentication.

- The `iam-renewer` sidecar checks the certificate daily.
- It renews it automatically before expiration.
- No further tokens are required.
