# Deployment Guide

This document outlines the steps to deploy and configure the `infra-iam` environment.

## 1. Prerequisites

- **Docker & Docker Compose**: v2.x or later.
- **Infra-PKI**: Must be running and accessible.
- **Active Directory**: (Optional) If enabling LDAP federation.

## 2. Configuration

1. **Configure `.env`**:
    Copy `.env.example` (if available) or edit `.env` directly.
    See [CONFIGURATION.md](./CONFIGURATION.md) for variable details.

2. **Establish Trust (PKI)**:
    You must configure the system to trust your internal PKI.

    **Option A: Automated (Recommended)**
    1. On `infra-pki` host: `./scripts/infra-pki/generate_token.sh` -> Output `iam-host_join_pki.env`.
    2. Copy file to this host.
    3. Run: `./scripts/infra-iam/configure_iam_pki.sh <path_to_env_file>`

    **Option B: Manual**
    Edit `.env` and set `CA_URL` and `FINGERPRINT` manually.

## 3. Deployment

1. **Start Services**:

    ```bash
    cd infra-iam
    docker compose up -d
    ```

2. **Verify Initialization**:
    Check the `setup` logs to ensure certificates were fetched correctly.

    ```bash
    docker compose logs -f setup
    ```

## 4. Post-Deployment

1. **Access Keycloak**:
    Navigate to `https://sso.example.com` (or your configured domain).
    Login with `admin` / `${KC_ADMIN_PASSWORD}`.

2. **Configure LDAP (Active Directory)**:
    - Go to **User Federation**.
    - Add **LDAP**.
    - Connection URL: `ldaps://ad.example.com:636`
    - Use `Truststore SPI` or `Always Trust` (since we mount `ad_root_ca.crt`).
