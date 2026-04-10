# Infra-RStudio: Configuration Reference

Complete reference for all variables in `infra-rstudio/.env`.  
Copy `.env.example` to `.env` and fill in required values before deploying.

---

## Quick Start Checklist

The minimum required variables for a working deployment:

```dotenv
AUTH_BACKEND=sssd
HOST_DOMAIN=rstudio.example.com
CA_URL=https://pki.example.com:9000
CA_FINGERPRINT=<sha256-fingerprint>
SSL_CERT_PATH=/etc/ssl/certs/your-cert.pem
SSL_KEY_PATH=/etc/ssl/private/your-key.key
```

---

## Variable Reference

### Authentication

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `AUTH_BACKEND` | **Yes** | `sssd` | Auth backend: `sssd` (SSSD + PAM) or `samba` (Winbind) |

### Network & Ports

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `HOST_DOMAIN` | **Yes** | `botanical.example.com` | FQDN for Nginx portal and TLS |
| `HTTP_PORT` | No | `80` | Host port for HTTP redirect |
| `HTTPS_PORT` | No | `443` | Host port for HTTPS portal |
| `RSTUDIO_PORT` | No | `8787` | Host port for direct RStudio access |
| `IPV6_ENABLED` | No | `false` | Enable IPv6 in Nginx configuration |

### Image Versions

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `RSTUDIO_VERSION` | No | `2023.06.0` | RStudio Server version |
| `R_VERSION` | No | `4.3.1` | R language version |
| `IMAGE_TAG` | No | `latest` | Tag applied to locally built images |
| `OAUTH2_PROXY_IMAGE` | No | `quay.io/oauth2-proxy/oauth2-proxy` | oauth2-proxy base image |
| `OAUTH2_PROXY_TAG` | No | `v7.6.0` | oauth2-proxy pinned tag |

### Resource Limits

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `RSTUDIO_CPU_LIMIT` | No | `4.0` | CPU cores limit for RStudio container |
| `RSTUDIO_MEMORY_LIMIT` | No | `8G` | RAM limit for RStudio container |
| `RAMDISK_SIZE` | No | `8G` | tmpfs size for /dev/shm (R scratch) |
| `MAX_BLAS_THREADS` | No | `16` | Hard cap on R BLAS/OpenBLAS threads |

### SSL / TLS

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `SSL_CERT_PATH` | **Yes** | `/etc/ssl/certs/ssl-cert-snakeoil.pem` | Host path to TLS certificate (PEM) |
| `SSL_KEY_PATH` | **Yes** | `/etc/ssl/private/ssl-cert-snakeoil.key` | Host path to TLS private key |

### PKI Trust (Internal Step-CA)

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `CA_URL` | **Yes** (PKI) | *(empty)* | URL of the Step-CA server (e.g. `https://pki.example.com:9000`) |
| `CA_FINGERPRINT` | **Yes** (PKI) | *(empty)* | SHA256 fingerprint of the Root CA for verification |
| `STEP_TOKEN` | No | *(empty)* | One-time enrollment token for Nginx certificate provisioning |

> Set `CA_URL` and `CA_FINGERPRINT` automatically using:
> `scripts/infra-rstudio/configure_rstudio_pki.sh /path/to/join_pki.env`

### Persistence & Storage

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `HOST_HOME_DIR` | No | `/home` | Host path for local user home directories |
| `HOST_PROJECT_ROOT` | No | `/nfs/home` | Host path for NFS project directories |
| `HOST_OLLAMA_STORAGE` | No | `/var/lib/ollama` | Host path for Ollama model storage |

### RStudio Session Tuning

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `RSESSION_TIMEOUT_MINUTES` | No | `10080` | Session idle timeout in minutes (10080 = 1 week) |
| `RSESSION_WEBSOCKET_LOG_LEVEL` | No | `1` | Log verbosity: 1=Error, 2=Warn, 3=Info, 4=Debug |
| `RSESSION_COPILOT_ENABLED` | No | `0` | GitHub Copilot: 0=disabled, 1=enabled |
| `OPENBLAS_NUM_THREADS` | No | `4` | OpenBLAS thread count |
| `OMP_NUM_THREADS` | No | `4` | OpenMP thread count |
| `PYTHON_ENV` | No | `/opt/r-geospatial` | Python venv path for `reticulate` |

### Active Directory / Kerberos

These variables are used by the `sssd` and `samba` entrypoint scripts:

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `DEFAULT_AD_DOMAIN_LOWER` | AD | `personale.dir.unibo.it` | AD domain (lowercase FQDN) |
| `DEFAULT_AD_DOMAIN_UPPER` | AD | `PERSONALE.DIR.UNIBO.IT` | Kerberos realm |
| `DEFAULT_COMPUTER_OU_BASE` | AD | *(UNIBO default)* | Base OU for computer accounts |
| `DEFAULT_HOME_TEMPLATE` | No | `/nfs/home/%U` | Home directory template |
| `DEFAULT_SIMPLE_ALLOW_GROUPS` | No | *(UNIBO groups)* | Comma-separated AD groups allowed |

### SSSD-Specific

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `HOST_SSS_PIPES` | sssd | `/var/lib/sss/pipes` | Host path to SSSD pipe directory |
| `HOST_SSS_MC` | sssd | `/var/lib/sss/mc` | Host path to SSSD memory cache |
| `HOST_SSSD_CONF` | sssd | `/etc/sssd/sssd.conf` | Host path to sssd.conf |
| `DEFAULT_USE_FQNS` | No | `false` | Use fully qualified user names |

### Samba/Winbind-Specific

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `HOST_WINBINDD_DIR` | samba | `/var/run/samba/winbindd` | Host path to Winbind socket directory |
| `HOST_SAMBA_DIR` | samba | `/var/lib/samba` | Host path to Samba state directory |
| `HOST_SMB_CONF` | samba | `/etc/samba/smb.conf` | Host path to smb.conf |
| `USE_WINBIND` | No | `true` | Use Winbind for ID mapping |

### Common Auth Mounts

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `HOST_KRB5_CONF` | AD | `/etc/krb5.conf` | Host path to Kerberos config |
| `HOST_NSSWITCH_CONF` | No | `/etc/nsswitch.conf` | Host path to nsswitch.conf |
| `DOCKER_USERID` | No | `1000` | UID for the container's internal user |
| `DOCKER_GROUPID` | No | `1000` | GID for the container's internal user |

### Ollama AI Engine

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `OLLAMA_MAX_LOADED_MODELS` | No | `1` | Max concurrent models in RAM |
| `OLLAMA_KEEP_ALIVE` | No | `24h` | How long to keep model loaded after last request |
| `OLLAMA_NUM_PARALLEL` | No | `2` | Parallel execution streams |
| `OLLAMA_HOST_BIND` | No | `127.0.0.1:11434` | Bind address for Ollama API |

### Telemetry API

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `TELEMETRY_HOST_ROOT` | No | `/` | Host root for psutil filesystem stats |
| `TELEMETRY_HOST_RUN` | No | `/var/run` | Host run directory for socket stats |
| `TELEMETRY_NFS_HOME` | No | `/hostfs/nfs/home` | NFS home path as seen inside container |
| `TELEMETRY_PROJECTS_DIR` | No | `/hostfs/nfs/projects` | Projects path as seen inside container |
| `ENABLE_TELEMETRY_STRIP` | No | `true` | Show telemetry strip on portal login page |

### Web Portal

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `BIOME_CONTACT` | No | `support@botanical.example.com` | Support email shown on portal |
| `NEXTCLOUD_TARGET_URL` | No | `https://192.168.1.100` | Nextcloud URL for portal links |
| `NGINX_WORKER_PROCESSES` | No | `auto` | Nginx worker process count |
| `NGINX_WORKER_CONNECTIONS` | No | `1024` | Max connections per Nginx worker |

---

## Compose Profile System

The stack uses Docker Compose profiles to enable optional components. Activate profiles using the `--profile` flag:

| Profile | Services Enabled | When to Use |
| :--- | :--- | :--- |
| `sssd` | `rstudio-sssd` | Host is domain-joined via SSSD |
| `samba` | `rstudio-samba` | Host uses Winbind/Samba for domain auth |
| `portal` | `nginx-portal` | Always required for HTTPS access |
| `oidc` | `oauth2-proxy` | Keycloak SSO is configured |
| `ai` | `ollama-ai` | Local LLM assistant is desired |

**Example — standard SSSD deployment with OIDC SSO:**
```bash
docker compose --profile sssd --profile portal --profile oidc up -d --build
```

**Note:** `rstudio-init`, `telemetry-api`, and `docker-socket-proxy` always start regardless of profiles.
