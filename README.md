# Infra-Iam-PKI Documentation

**Version:** 1.0.0
**Maintainer:** DevOps Team

## 1. Project Overview

This repository contains the Infrastructure-as-Code (IaC) for the internal **Public Key Infrastructure (PKI)** and **Identity and Access Management (IAM)** systems. It relies on Docker Compose for orchestration and provides a suite of automation scripts for certificate lifecycle management.

### Key Components

* **Infra-PKI**: Hosted using [Smallstep CA](https://smallstep.com/). Provides internal TLS certificates.
* **Infra-IAM**: Hosted using [Keycloak](https://www.keycloak.org/) behind [Caddy](https://caddyserver.com/). Authenticates users (optionally via Active Directory LDAPS).
* **Automation Scripts**: A toolkit to bootstrap trust, request certificates, and perform maintenance.

---

## 2. Directory Structure

```plaintext
Infra-Iam-PKI/
├── infra-pki/                  # PKI Service (Root CA)
│   ├── docker-compose.yml      # Step CA, Watchtower, Setup, Fingerprint-Writer
│   ├── step_data/              # Persistent CA data (Keys, Config, DB)
│   └── .env                    # Configuration (Passwords, Domain)
│
├── infra-iam/                  # IAM Service (Keycloak + SSO)
│   ├── docker-compose.yml      # Keycloak, Caddy, Postgres, Watchtower, Setup, Renewer
│   ├── certs/                  # Auto-fetched certificates (do not commit)
│   └── .env                    # Configuration (AD connection, PKI URL)
│
└── scripts/                    # Automation Toolkit
    ├── fetch_root_ca.sh        # Bootstraps trust with the PKI
    ├── fetch_ad_cert.sh        # Bootstraps trust with Active Directory
    ├── get_certificate.sh      # Requests new certificates (OTT/Token)
    ├── renew_certificate.sh    # Renews existing certificates
    ├── setup_client_trust.sh   # Configures Linux clients to trust CA
    └── maintenance_docker.sh   # System cleanup and monitoring
```

---

## 3. Deployment Guide

### Phase 1: Deploy PKI

The PKI must be online first as IAM depends on it.

1. **Configure:** Edit `infra-pki/.env` (Set `DOMAIN_CA`, `CA_PASSWORD`, `DNSS`).
2. **Start:**

    ```bash
    cd infra-pki
    docker compose up -d
    ```

3. **Verify:**
    * Check `step_data/fingerprint` exists (created by `fingerprint-writer`).
    * Ensure `https://<ca-domain>:9000/health` is reachable.

### Phase 2: Deploy IAM

IAM services will auto-configure their certificates on first launch.

1. **Configure:** Edit `infra-iam/.env` (Set `CA_URL`, `AD_HOST`).
2. **Start:**

    ```bash
    cd infra-iam
    docker compose up -d
    ```

    *The `setup` service will fetch the Root CA and AD Certs automatically before Keycloak starts.*

---

## 4. Certificate Management (Scripts)

Scripts are located in `scripts/`. They are designed to run on the host or in containers.

### Obtaining a Certificate (New Service)

Use `get_certificate.sh` to request a certificate. It supports auto-discovery of configuration.

```bash
# Usage: ./get_certificate.sh <hostname> <sans>
./scripts/get_certificate.sh my-service.biome.unibo.it
```

* **Authentication:** Prompts for CA Admin password OR uses `CA_PASSWORD` env var to generate a One-Time Token (OTT).
* **Security:** Private keys are generated locally and never leave the host.

### Renewing a Certificate

Certificates are short-lived (default 24h). Renewals are automated.

```bash
./scripts/renew_certificate.sh /path/to/cert.crt /path/to/key.key
```

* **Exit Codes:** `0` (Renewed), `2` (No change needed/Failed). Use this to trigger service restarts.

### Maintenance

Run the script without arguments to see the menu:

```bash
./scripts/maintenance_docker.sh
```

Or use direct commands:

* `monitor`: View stats.
* `prune`: Clean unused resources.
* `nuke`: **Reset System** (Stops all, removes images/volumes/networks/cache).

---

## 5. Onboarding New Hosts

To configure a new server (e.g., a web server, database, or Kubernetes node) to use this PKI:

1. **Copy Scripts:** Transfer the `scripts/` directory to the new host.
2. **Establish Trust:**

    ```bash
    ./scripts/setup_client_trust.sh https://ca.biome.unibo.it:9000 <fingerprint>
    ```

    *This installs the Root CA into the OS trust store (`/usr/local/share/ca-certificates`).*
3. **Request Certificate:**

    ```bash
    ./scripts/get_certificate.sh new-host.biome.unibo.it
    ```

4. **Automate Renewal:**
    Add a cron job to renew daily:

    ```cron
    0 3 * * * /path/to/scripts/renew_certificate.sh /path/to/cert.crt /path/to/cert.key && systemctl reload my-service
    ```

---

## 6. Troubleshooting

### `step-ca` fails to start "password file not found"

* **Cause:** The `setup` container in `infra-pki` failed to write the password.
* **Fix:** Check permissions on `infra-pki/step_data`. Ensure the `setup` service ran successfully.

### "x509: certificate signed by unknown authority"

* **Cause:** The client does not trust the Root CA.
* **Fix:** Run `./scripts/setup_client_trust.sh` or ensure `infra-iam` mounted the `root_ca.crt` correctly.

### Watchtower "Client version 1.25 is too old"

* **Cause:** Docker Compose file using old protocol.
* **Fix:** Ensure `DOCKER_API_VERSION=1.44` is set in Watchtower environment (already applied in `docker-compose.yml`).

### Re-initializing PKI (Changing Domain/Passwords)

* **Problem:** Changing `DOMAIN_CA` or passwords in `.env` has no effect.
* **Cause:** `step-ca` only initializes once. Subsequent runs use the persisted configuration in the `step_data` volume.
* **Fix:** You must manually delete the data to force a rebuild.

    ```bash
    cd infra-pki
    docker compose down
    sudo rm -rf step_data/   # ⚠️ WARNING: Deletes all existing keys/certs!
    sudo rm -rf logs/
    docker compose up -d
    ```

    *Note: After this, the Root CA Fingerprint will change. Update `infra-iam/.env` and re-issue all service certificates.*

---

## 7. Best Practices & Security

### Secrets Management

* **Current:** Passwords are in `.env` files.
* **Recommendation:** For production, move sensitive credentials (CA password, DB password) to **Docker Secrets** or a Vault (HashiCorp Vault).

### Root CA Protection

* The Root Key is currently online (in `step_data/secrets`).
* **High Security:** Move the Root CA to an offline machine (air-gapped) and use an **Intermediate CA** in Docker for daily signing.

### Monitoring

* Container logs are rotated (`json-file`, max 15MB).
* Use `maintenance_docker.sh monitor` for quick checks.
* **Future:** Ship logs to an ELK stack or Graylog.

---

## 8. Future Roadmap: High Availability (HA)

To move this setup to a Clustered/HA environment (Kubernetes):

1. **Storage:** The `step_data` volume must be shared (PVC, NFS, or Ceph) OR use an external Database (PostgreSQL/MySQL) for Step CA.
2. **Identity:** Keycloak handles Clustering natively (Infinispan). It requires `JDBC_PING` or `DNS_PING` for discovery.
3. **Ingress:** Replace Caddy with Nginx Ingress Controller or Traefik, terminating TLS using certificates managed by **cert-manager**.
    * **Cert-Manager Integration:** `cert-manager` has a native `StepIssuer`. It can talk directly to your `infra-pki` to provision certs for K8s pods automatically.

---
*Generated by Antigravity Assistant*
