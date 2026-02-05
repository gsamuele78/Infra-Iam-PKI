# Configuration Reference

## 1. Step-CA Configuration

The CA is configured primarily via `docker-compose.yml` environment variables which feed into the `init_step_ca.sh` script.

### 1.1 Provisioners

The initialization script dynamically creates provisioners if they don't exist.

| Provisioner Type | Env Var Trigger | Purpose |
| :--- | :--- | :--- |
| **OIDC** | `OIDC_CLIENT_ID` + `OIDC_CLIENT_SECRET` | User Authentication, Single Sign-On (SSO) for SSH. |
| **ACME** | `ENABLE_ACME=true` | Automated X.509 certificate issuance (like Let's Encrypt). |
| **SSH-POP** | `ENABLE_SSH_PROVISIONER=true` | **RENEWAL** of SSH Host Certificates. Proves possession of existing cert. |
| **JWK (Host)** | `SSH_HOST_PROVISIONER_PASSWORD` | **INITIAL** issuance of SSH Host Certificates. Password-based bootstrap. |

### 1.2 SSH Lifecycle Strategy

We utilize a split provisioner strategy for SSH Hosts aka "Best Practice":

1. **Bootstrap (Day 0)**: Use the **JWK** provisioner (`ssh-host-jwk`).
    * Command: `step ca certificate --provisioner ssh-host-jwk ...`
    * Auth: Uses the shared password defined in `.env`.
2. **Renewal (Day N)**: Use the **SSH-POP** provisioner (`ssh-pop`).
    * Command: `step ca renew ...`
    * Auth: Uses the existing valid host certificate to sign the request.

## 2. Proxy Configuration (Caddy)

The `infra-pki/caddy/Caddyfile` defines the ingress rules.

### 2.1 Layer 4 Proxying

We use the `layer4` directive to proxy TCP traffic.

* **Why?** This allows `step-ca` to handle mutual TLS (mTLS) directly if needed, without the proxy terminating TLS. It keeps the proxy logic simple (IP filtering & forwarding).

### 2.2 IP Allowlisting

Defined in `.env` as `ALLOWED_IPS`.

* Format: Space-separated CIDR blocks (e.g., `127.0.0.1/32 10.0.0.0/8`).
* Mechanism: Caddy's `@allowed` matcher drops connections from undefined IPs before they reach `step-ca`.

## 3. Database Configuration

PostgreSQL is configured strictly for internal access.

* **User/Pass**: Defined in `.env`.
* **Persistence**: Data stored in `./infra-pki/db_data`.
* **Connection**: `step-ca` connects via the Docker service name `postgres`.
