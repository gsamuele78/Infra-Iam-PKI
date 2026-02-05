# Infra-IAM-PKI: System Overview

## 1. Executive Summary

This project implements a robust, production-grade Public Key Infrastructure (PKI) and Identity Access Management (IAM) system. The core PKI component (`infra-pki`) utilizes **Smallstep CA** (`step-ca`) to provide internal TLS and SSH certificate management.

The architecture is designed for **high availability**, **security**, and **observability**, leveraging industry-standard components like **PostgreSQL** for data persistence and **Caddy** for secure Layer 4 proxying.

## 2. Architecture

### 2.1 Components

* **Step-CA**: The core Certificate Authority service.
* **PostgreSQL 15**: Dedicated database backend for `step-ca` to ensure data integrity, support HA scaling, and handle high concurrency. Replaces the default file-based BadgerDB.
* **Caddy (Layer 4)**: A custom-built reverse proxy that handles incoming TCP traffic. It effectively masks the CA backend and provides a control layer for **IP Allowlisting**.
* **Initialization Scripts**: Dynamic Bash scripts that auto-configure complex provisioners (OIDC, SSH-POP, ACME) on container startup, reducing manual configuration drift.

### 2.2 Network Flow

1. **Ingress**: Client requests (ACME, OIDC, API) hit the **Caddy** proxy on port `9000`.
2. **Filtering**: Caddy validates the source IP against the `ALLOWED_IPS` environment variable.
3. **Forwarding**: Allowed traffic is proxied via TCP (Layer 4) to the **Step-CA** container on the internal Docker network.
4. **Persistence**: Step-CA reads/writes state to the **PostgreSQL** database, which is isolated from the host network (no exposed ports).

## 3. Key Features

* **Secure Backend**: Transitioned from embedded database to Postgres for enterprise reliability.
* **Automated Provisioning**: OIDC (User/SSH) and ACME provisioners are configured automatically via environment variables.
* **SSH Certificate Management**:
  * **JWK Provisioner**: For initial bootstrapping of SSH hosts.
  * **SSH-POP Provisioner**: For secure, automated renewal of host certificates.
* **Host Trust Management**: Dedicated script `manage_host_trust.sh` to safely install the internal Root CA on the host OS.

## 4. Security Considerations

* **Network Isolation**: Database is not exposed. CA is only accessible via the Proxy.
* **Secrets Management**: Critical secrets (CA password, OIDC Client Secret) are injected via `docker-compose.yml` from a secured `.env` file. *Recommendation: Integrate with **Docker Secrets** (Open Source) or **OpenBao** (Open Source fork of Vault) in production.*
* **Ephemeral Tokens**: Uses short-lived tokens for provisioning to minimize attack surface.
