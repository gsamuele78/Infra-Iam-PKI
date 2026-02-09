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

| Variable | Description | Example |
|---|---|---|
| `DOMAIN_CA` | DNS for the CA | `ca.example.com` |
| `PKI_NAME` | CA Subject/Issuer Name | `Internal Root CA` |
| `CA_PASSWORD` | Password for the Root CA Key | *ChangeMe* |
| `POSTGRES_DB` | Database Name | `step_ca_db` |
| `ALLOWED_IPS` | CIDR blocks allowed to access CA | `127.0.0.1/32 ...` |
| `ENABLE_SSH_PROVISIONER`| Enable SSH Host support | `true` |
| `SSH_HOST_PROVISIONER_PASSWORD` | Password for SSH Host JWK | *ChangeMe* |

## 3. Fresh Installation (Preferred Method)

The recommended way to deploy the stack is using the automation scripts. These handle permissions, directory creation, image building, and startup.

1. **Configure Environment**:

    ```bash
    cd ../scripts/infra-pki
    ./configure_pki.sh
    ```

    (Use this menu to set passwords safely and toggle features)

2. **Deploy**:

    ```bash
    ./deploy_pki.sh
    ```

    This script will:
    * Validate configuration
    * Fix Caddyfile (if needed)
    * Create required directories
    * Set correct permissions
    * Build/Pull images
    * Start services
    * Wait for health checks

3. **Initialization**:
    The system initializes automatically on first run. You can verify it with:

    ```bash
    ./verify_pki.sh
    ```

## 4. Manual Installation (Docker Compose)

If you prefer to run `docker compose` directly (e.g., for debugging), follow these steps:

1. **Prepare Directories**:

    ```bash
    cd ../../infra-pki
    mkdir -p step_data db_data logs/step-ca logs/postgres logs/caddy
    # Ensure PUID/PGID matches what's used in .env
    sudo chown -R 1000:1000 step_data db_data logs
    ```

2. **Build and Start**:

    ```bash
    docker compose up -d --build
    ```

## 5. Maintenance & Reset

### Full Reset (Destroy Data)

To completely wipe the PKI environment (delete all keys, certificates, and database data) and start over:

```bash
cd ../scripts/infra-pki
./reset_pki.sh
```

> **Warning**: This action is irreversible. All clients will need to re-enroll.

### Backup

To backup the current state (keys, config, database):

```bash
./backup_pki.sh
```

Backups are stored in `/backup/infra-pki/`.

## 6. Host Trust

To allow your host machine to trust certificates issued by this internal CA:

1. Run the trust manager:

    ```bash
    sudo ./manage_host_trust.sh
    ```

2. Select **Option 1 (Install/Trust)**.

## 7. Client Enrollment

To enroll a remote host (e.g., `infra-iam`):

1. **Generate Token** (on Server):

    ```bash
    ./generate_token.sh
    ```

    (Follow prompts. Output: `<hostname>_join_pki.env`)

2. **Deploy to Client**:
    Copy `client/join_pki.sh` and the generated `.env` to the client.

3. **Join** (on Client):

    ```bash
    sudo ./join_pki.sh ssh-host
    ```
