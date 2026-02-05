# Deployment Guide

This document outlines the steps to initialize, deploy, and verify the `infra-pki` environment.

## 1. Prerequisites

* Docker & Docker Compose (v2.x recommended)
* Git
* `sudo` privileges for port binding (9000) and trust script execution.

## 2. Configuration (`.env`)

Before starting, ensure `infra-pki/.env` is configured.
> **Critical**: Do not commit the `.env` file to version control.

| Variable | Description | Default |
| :--- | :--- | :--- |
| `DOMAIN_CA` | DNS for the CA | `ca.example.com` |
| `CA_PASSWORD` | Password for the Root CA Key | *ChangeMe* |
| `POSTGRES_DB` | Database Name | `step_ca_db` |
| `ALLOWED_IPS` | CIDR blocks allowed to access CA | `127.0.0.1/32 ...` |
| `ENABLE_SSH_PROVISIONER`| Enable SSH Host support | `true` |
| `SSH_HOST_PROVISIONER_PASSWORD` | Password for SSH Host JWK | *ChangeMe* |

## 3. Fresh Installation

If initializing for the first time or after a reset:

1. **Clean State** (Optional):

    ```bash
    cd infra-pki
    docker compose down -v
    sudo rm -rf step_data db_data
    ```

2. **Build and Start**:

    ```bash
    docker compose up -d --build
    ```

    *Note: The first build creates the custom Caddy image and may take 1-2 minutes.*

3. **Initialization**:
    The `setup` container will run `init_step_ca.sh`. Monitor logs to ensure success:

    ```bash
    docker compose logs -f setup
    ```

## 4. Host Trust

To allow your host machine to trust certificates issued by this internal CA:

1. Navigate to scripts:

    ```bash
    cd ../scripts
    ```

2. Run the trust manager:

    ```bash
    sudo ./manage_host_trust.sh
    ```

3. Select **Option 1 (Install/Trust)**.

## 5. Verification

Run the following checks to confirm operational status:

1. **Health Endpoint**:

    ```bash
    curl -k https://localhost:9000/health
    # Expected: {"status":"ok"}
    ```

2. **Fingerprint**:
    The system should auto-generate the root fingerprint in `infra-pki/step_data/fingerprint`.

    ```bash
    cat infra-pki/step_data/fingerprint
    ```
