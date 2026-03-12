# Infra-OOD: System Overview

## 1. Executive Summary

This component (`infra-ood`) serves as a production-grade frontend gateway for high-performance computing tasks, specifically interfacing with the `R-studioConf` containers. It provides a web-based dashboard for users to launch interactive applications securely, leveraging the official **Open OnDemand** project architecture.

The architecture is designed strictly around the project's **Pessimistic System Engineering** constraints, featuring decoupling, immutable initialization, resource limits, and Zero-Trust integration with internal IAM and PKI services.

## 2. Architecture

### 2.1 Core Components

- **Apache HTTP Server (Front-End Reverse Proxy)**: Open OnDemand utilizes Apache as the primary gateway. It handles user authentication via `mod_auth_openidc`, acts as a reverse proxy, and initiates **Per-User NGINX (PUN)** processes.
- **Per-User NGINX (PUN)**: When a user authenticates, a dedicated, unprivileged NGINX server (PUN) is spawned under their UUID. Apache proxies requests to the PUN via Unix domain sockets. The PUN then reverse-proxies connections to interactive apps (like `R-studioConf`) over TCP.
- **Init Container (`ood-init`)**: A custom, immutable Alpine container that dynamically queries the `infra-pki` network to fetch and install the required Root CA certificates securely on host boot, discarding the need to share host-level volumes.

### 2.2 Network Flow

1. **Ingress**: A user hits the portal (e.g., `https://ood.example.com`).
2. **Authentication Interception**: The Apache frontend intercepts the request. Since no active session exists, the `mod_auth_openidc` plugin redirects the user to the `infra-iam` (Keycloak) Identity Provider for SSO.
3. **Internal Trust**: Keycloak validates the user and issues a token. The Apache reverse proxy verifies this token against Keycloak's public keys (TLS integrity is backed by the dynamically fetched `infra-pki` Root CA).
4. **PUN Spawning**: Upon successful login, Apache spawns a PUN for the user.
5. **Interactive Proxying**: The user accesses an app (e.g. RStudio). The PUN reverse proxies the WebSocket and HTTP traffic to the isolated `docker-deploy` network nodes.

## 3. Security Considerations & Multi-Host Architecture (PRD Compliant)

- **Multi-Host Decoupling**: OOD can be deployed on a completely separate server from `infra-iam` and `infra-pki`. It obtains its internal TLS certificates by querying the PKI via the network API (using `fetch_pki_root.sh`).
- **Pessimistic Security Restraints**: The `ood-portal` container is strictly capped regarding CPU (`cpus`) and Memory (`memory`) limits via cgroups in `docker-compose.yml`. This prevents excessive frontend memory leaks or high user concurrency from crashing the host kernel.
- **Immutable Initialization**: Initial setup and cert fetching are handled by a dedicated `ood-init` container built on a custom, immutable Alpine `Dockerfile` without relying on runtime package installations (`apk add`).
- **Zero-Trust Auth Offloading**: Individual interactive applications (like RStudio or Jupyter) do not require their own authentication mechanisms; the burden is entirely offloaded to the centralized Apache reverse proxy and Keycloak.

## 4. Custom BiGeA UI Theming

The visual presentation of Open OnDemand has been heavily customized to match the strict branding guidelines of the **BiGeA Department (University of Bologna)**, referencing `https://bigea.unibo.it/it`.

- A dedicated CSS file (`bigea-theme.css`) is injected into the OOD portal via `ood_portal.yml`.
- Implements the academic **Unibo Red** palette.
- Replaces standard bootstrap panels with modern, premium **Glassmorphism** overlays matching the Keycloak SSO login experience.
- Implements a strict `system-ui` typography stack, explicitly avoiding external CDNs (like Google Fonts) to guarantee Zero-Trust / Airgap compliance.
