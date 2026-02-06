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

    * Auth: Uses the existing valid host certificate to sign the request.

### 1.3 Dynamic Configuration Patching

To support complex passwords and PostgreSQL connection requirements that are not natively handled by the `step-ca` 0.29.0 initialization:

* **Script**: `scripts/infra-pki/patch_ca_config.sh`
* **Execution**: Runs as a pre-start step in the `step-ca` container (entrypoint override).
* **Function**:
    1. Reads `PGUSER`, `PGPASSWORD`, `PGDATABASE`.
    2. **URL Encodes** credentials (fixes issues with special chars like `#`, `@`).
    3. Constructs a DSN with `?sslmode=disable` (required for internal container networking).
    4. Patches `ca.json` using `jq` to enforce `"type": "postgresql"`.

## 2. Proxy Configuration (Caddy)

The `infra-pki/caddy/Caddyfile` defines the ingress rules.

### 2.1 Layer 4 Proxying

We use the `layer4` directive to proxy TCP traffic.

* **Why?** This allows `step-ca` to handle mutual TLS (mTLS) directly if needed, without the proxy terminating TLS. It keeps the proxy logic simple (IP filtering & forwarding).
* **Health Check**: Since `layer4` does not expose an HTTP endpoint on the standard port, Docker health checks use `nc -z localhost 9000` to verify the TCP listener is active.

### 2.2 IP Allowlisting

Defined in `.env` as `ALLOWED_IPS`.

* Format: Space-separated CIDR blocks (e.g., `127.0.0.1/32 10.0.0.0/8`).
* Mechanism: Caddy's `@allowed` matcher drops connections from undefined IPs before they reach `step-ca`.

## 3. Database Configuration

PostgreSQL is configured strictly for internal access.

* **User/Pass**: Defined in `.env`.
* **Persistence**: Data stored in `./infra-pki/db_data`.
* **Connection**: `step-ca` connects via the Docker service name `postgres`.
