# Infra-IAM: Identity & Access Management

This component provides a centralized SSO (Single Sign-On) solution using **Keycloak**, secured by **Caddy** and integrated with Active Directory (AD) and the internal PKI.

## Architecture

```mermaid
graph TD
    User([User]) -->|HTTPS| Caddy[Caddy Reverse Proxy]
    Caddy -->|HTTP| Keycloak[Keycloak]
    Keycloak -->|SQL| Postgres[PostgreSQL DB]
    Keycloak -->|LDAPS| AD[Active Directory]
    
    subgraph "Trust & Security"
        PKI[Infra-PKI] -.->|Root CA| Keycloak
        PKI -.->|Root CA| Caddy
    end
```

## Services

| Service | Description | Credentials |
| :--- | :--- | :--- |
| **keycloak** | The Identity Provider (IdP) | Admin: `admin` / `${KC_ADMIN_PASSWORD}` |
| **db** | PostgreSQL backend for Keycloak | User: `keycloak` / `${DB_PASSWORD}` |
| **caddy** | TLS Termination & Reverse Proxy | Auto-managed Certificates |
| **setup** | Init container for fetching certs | Internal usage |
| **renewer** | Auto-renews internal certificates | Internal usage |

## Integrations

- **Infra-PKI**: The system trusts the internal Root CA to enable secure communication with other internal services.
- **Active Directory**: Integrated via LDAPS for user federation (requires `fetch_ad_cert.sh`).
