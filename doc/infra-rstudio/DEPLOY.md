# Infra-RStudio: Deployment Guide

This guide covers the full operator workflow for deploying `infra-rstudio` on a production host.

---

## Prerequisites

Before deploying, ensure the following conditions are met on `rstudio-host`:

| Requirement | Check |
| :--- | :--- |
| Docker Engine + Compose plugin installed | `docker compose version` |
| Host joined to AD domain (if using `sssd` or `samba` profile) | `realm list` or `wbinfo -t` |
| SSSD or Winbind configured on host (see auth backend selection) | `systemctl is-active sssd` |
| `infra-pki` Step-CA is running and reachable | `curl http://192.168.56.10/fingerprint/root_ca.fingerprint` |
| `.env` file created from `.env.example` | `ls infra-rstudio/.env` |

---

## Step 1: Prepare the Environment File

```bash
cd /path/to/Infra-Iam-PKI
cp infra-rstudio/.env.example infra-rstudio/.env
```

Edit `infra-rstudio/.env` and fill in at minimum:

```dotenv
AUTH_BACKEND=sssd           # or: samba
HOST_DOMAIN=rstudio.example.com
RSTUDIO_PORT=8787
HTTPS_PORT=443
```

See [CONFIGURATION.md](./CONFIGURATION.md) for the full variable reference.

---

## Step 2: Inject PKI Trust Configuration

Once `infra-pki` has been initialized and a join token file generated:

```bash
# The join file is produced by scripts/infra-pki/generate_token.sh
scripts/infra-rstudio/configure_rstudio_pki.sh /path/to/infra-rstudio_join_pki.env
```

This updates `.env` with `CA_URL` and `CA_FINGERPRINT`. Verify:

```bash
grep -E '^(CA_URL|CA_FINGERPRINT)=' infra-rstudio/.env
```

---

## Step 3: Pre-Deploy Validation

```bash
scripts/infra-rstudio/validate_rstudio.sh --pre-deploy
```

This checks:
- Required `.env` variables are set
- Docker Compose configuration is valid
- `docker.sock` is present (needed by `docker-socket-proxy`)
- Auth backend sockets exist (SSSD or Winbind)

Fix any errors reported before proceeding.

---

## Step 4: Deploy

```bash
scripts/infra-rstudio/deploy_rstudio.sh
```

The script will:
1. Assert dependencies (`docker`, `curl`)
2. Safe-parse `.env` (never `source` it directly)
3. Show a confirmation prompt with active backend and domain
4. Run `docker compose --profile <AUTH_BACKEND> --profile portal up -d --build`
5. Wait for services and report health status

### Optional Profiles

To activate additional components, pass profile flags:

```bash
# With Keycloak OIDC SSO
docker compose --profile sssd --profile portal --profile oidc up -d --build

# With local Ollama AI assistant
docker compose --profile sssd --profile portal --profile ai up -d --build

# All profiles
docker compose --profile sssd --profile portal --profile oidc --profile ai up -d --build
```

**Note**: Deploy `oauth2-proxy.cfg` before activating the `oidc` profile:
```bash
cp infra-rstudio/config/oauth2-proxy.cfg.example infra-rstudio/config/oauth2-proxy.cfg
# Edit oauth2-proxy.cfg with real Keycloak client credentials
```

---

## Step 5: Post-Deploy Verification

```bash
scripts/infra-rstudio/validate_rstudio.sh --post-deploy
```

Or manually check:

```bash
# Container health
docker compose -f infra-rstudio/docker-compose.yml ps

# RStudio UI is responding
curl -sf http://localhost:${RSTUDIO_PORT:-8787}

# Nginx portal (HTTPS)
curl -sf --cacert infra-rstudio/certs/root_ca.crt https://${HOST_DOMAIN}

# Telemetry API
curl -sf http://localhost:5000/health
```

---

## Updating Trust Store (PKI Root CA Changed)

If `infra-pki` is re-initialized and the Root CA changes:

1. Get the new join env file from the PKI operator
2. Re-run configure: `scripts/infra-rstudio/configure_rstudio_pki.sh /path/to/new.env`
3. Restart init container to re-fetch: `docker compose restart rstudio-init`
4. Restart nginx: `docker compose restart nginx-portal`

---

## Backup

```bash
scripts/infra-rstudio/backup_rstudio.sh
```

Backs up SSL certificates, `.env` (redacted), and infrastructure state. Does **not** back up user R session data (located on NFS mounts, managed separately).

---

## Teardown / Reset

```bash
scripts/infra-rstudio/reset_rstudio.sh
```

> ⚠️ This stops and removes all containers and volumes. Use only for full redeployment.

---

## Container Architecture Reference

### Dockerfile Topology

| Dockerfile | Base Image | Role | Key Features |
| :--- | :--- | :--- | :--- |
| `Dockerfile.sssd` / `Dockerfile.samba` | `rocker/geospatial` (Ubuntu LTS) | Primary compute container | AD integration (SSSD/Winbind), PPA `c2d4u` for binary R packages via `bspm` |
| `Dockerfile.nginx` | `nginx:alpine` | Reverse proxy + UI portal | Custom templates, `gettext` for runtime interpolation, security headers |
| `Dockerfile.telemetry` | `python:3.11-slim` | Async metrics API | Version-pinned FastAPI/Pydantic, runs as non-root |

### Entrypoint Boot Phases

**`entrypoint_rstudio.sh`** executes 4 phases before starting RStudio:

1. **PKI Trust Ingestion** — Checks `$CA_URL`. If set, imports Root CA into the OS trust store via `manage_pki_trust.sh`
2. **Resource Constraint Injection** — Reads compose `deploy.resources` limits (CPU cores, RAM) and converts them to `Renviron.site` values for OpenBLAS/OMP thread calibration
3. **Template Sandboxing** — Uses `mktemp` to generate `Rprofile.site` and `rserver.conf` from `.env` variables, preventing I/O race conditions
4. **Auth Binding** — Modifies `/etc/nsswitch.conf` to trust host-side LDAP pipes (SSSD or Winbind)

**`entrypoint_nginx.sh`** executes 3 phases:

1. **Certificate Check** — Verifies existing certs or enrolls new ones via `pki/enroll_cert.sh` if Step-CA integration is configured
2. **Portal Generation** — Uses `process_template()` to render the Botanical Portal HTML from feature flags in `.env`
3. **Hardened Config** — Replaces default `nginx.conf` with DDoS-mitigated tuning (limited buffers, coordinated timeouts)

