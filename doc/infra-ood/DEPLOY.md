# Open OnDemand Deployment Guide

This guide covers the "Clean Method" architecture used to deploy the `infra-ood` stack, matching the pessimistic system engineering standards applied to `infra-pki` and `infra-iam`.

## Prerequisites

1. **Docker & Docker Compose**: Installed and active.
2. **Infra-PKI**: Must be running and accessible over the network (Required to fetch the Root CA).
3. **Infra-IAM**: Must be running, and the OIDC Client must be registered in Keycloak.

## Deployment Steps

1. **Configure Environment:**
   Copy the example environment template and populate it with the secrets and endpoints of your Keycloak and PKI servers.

   ```bash
   cp .env.example .env
   nano .env
   ```

2. **Execute Deployment Script:**
   The process is entirely encapsulated in the deployment script to guarantee zero-trust directory permissions.

   ```bash
   cd scripts/infra-ood
   ./deploy_ood.sh
   ```

   *Note: `deploy_ood.sh` will `exit 1` instantly if it fails to apply `PUID:PGID` ownership to the volume mounts, preventing frustrating "Permission Denied" errors deep inside the OOD logs.*

3. **Verify Startup Sequence:**
   The `ood-init` image will build from the immutable `Dockerfile.init` (containing baked-in dependencies) and fetch the certificates via API. Then, `ood-portal` will start.

   ```bash
   docker compose logs -f
   ```

## Teardown and Reset (The Clean Method)

When tearing down the environment for testing or migration, it is critical to avoid orphaned configurations or cached certificates.

To securely obliterate the environment, use the dedicated reset script:

```bash
cd scripts/infra-ood
./reset_ood.sh
```

**What this does:**

1. Triggers `docker compose down -v`.
2. Utilizes `sudo` (if necessary) to recursively delete `./certs` and `./data` host mounts.
3. Recreates the directories dynamically, asserting a 100% clean state for the next run.
