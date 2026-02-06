# Deployment Guide

This document outlines the steps to initialize, deploy, and verify the `infra-pki` environment.

## 1. Prerequisites

* Docker & Docker Compose (v2.x recommended)
* Git
* `openssl` (for certificate verification)
* `sudo` privileges for port binding (9000) and trust script execution.

## 2. Configuration (`.env`)

Before starting, ensure `infra-pki/.env` is configured.
> **Critical**: Do not commit the `.env` file to version control.

| `DOMAIN_CA` | DNS for the CA | `ca.example.com` |
| `PKI_NAME` | CA Subject/Issuer Name | `Internal Root CA` |
| `CA_PASSWORD` | Password for the Root CA Key | *ChangeMe* |
| `POSTGRES_DB` | Database Name | `step_ca_db` |
| `ALLOWED_IPS` | CIDR blocks allowed to access CA | `127.0.0.1/32 ...` |
| `ENABLE_SSH_PROVISIONER`| Enable SSH Host support | `true` |
| `SSH_HOST_PROVISIONER_PASSWORD` | Password for SSH Host JWK | *ChangeMe* |

## 3. Fresh Installation

If initializing for the first time or after a reset:

1. **Clean State** (Optional):
    You can use the dedicated reset script to safely wipe data:

    ```bash
    cd ../scripts/infra-pki
    sudo ./reset_pki.sh
    ```

2. **Build and Start**:

    ```bash
    cd ../../infra-pki
    docker compose up -d --build
    ```

    *Note: The first build creates the custom Caddy image and may take 1-2 minutes.*

3. **Initialization**:
    The `setup` container will run `init_step_ca.sh`. Monitor logs to ensure success:

    ```bash
    docker compose logs -f step-ca-configurator
    ```

## 4. Host Trust

To allow your host machine to trust certificates issued by this internal CA:

1. Navigate to scripts:

    ```bash
    cd ../scripts/infra-pki
    ```

2. Run the trust manager:

    ```bash
    sudo ./manage_host_trust.sh
    ```

3. Select **Option 1 (Install/Trust)**.
   You can also verify certificate details (Issuer, Validity) using **Option 3**.

## 5. Verification

Run the comprehensive verification script to confirm operational status:

```bash
./verify_pki.sh
```

This script checks:

* Container Health (Step-CA, Postgres, Caddy)
* Caddy Layer 4 Check (TCP Port 9000)
* Step-CA API connectivity
* Database Readability
* Provisioner Status (SSH, Admin, ACME)

## 6. Client Enrollment

To enroll a remote host (e.g., `infra-iam`):

1. **Generate Token** (on Server):

   ```bash
   ./generate_token.sh
   # Follow prompts. Output: <hostname>_join_pki.env
   ```

2. **Deploy to Client**:
   Copy `client/join_pki.sh` and the generated `.env` to the client.

3. **Join** (on Client):

   ```bash
   sudo ./join_pki.sh ssh-host
   ```
