# Infra-RStudio: Troubleshooting Guide

---

## Diagnostic Commands Quick Reference

```bash
# Container status and health
docker compose -f infra-rstudio/docker-compose.yml ps

# Logs for a specific service
docker compose -f infra-rstudio/docker-compose.yml logs --tail=50 nginx-portal
docker compose -f infra-rstudio/docker-compose.yml logs --tail=50 rstudio-sssd

# All logs since last deploy
docker compose -f infra-rstudio/docker-compose.yml logs --follow

# Run validate script
scripts/infra-rstudio/validate_rstudio.sh --post-deploy
```

---

## Failure Modes

### 1. SSSD Socket Not Found — Container Starts, Auth Fails

**Symptom**: RStudio starts but users cannot log in. `rstudio-sssd` logs show:
```
SSSD pipe directory not found: /var/lib/sss/pipes
```

**Cause**: SSSD is not running on the host, or `HOST_SSS_PIPES` in `.env` points to the wrong path.

**Resolution**:
```bash
# Verify SSSD is running on the host
systemctl is-active sssd

# Check actual pipe path on host
ls /var/lib/sss/pipes/

# If path is different, update .env
# HOST_SSS_PIPES=/correct/path/to/sss/pipes

# Restart SSSD if stopped
systemctl start sssd

# Restart the container to re-bind the socket
docker compose restart rstudio-sssd
```

---

### 2. PKI Root CA Missing — Nginx TLS Error

**Symptom**: `nginx-portal` container fails to start or is unhealthy. Logs show:
```
nginx: [emerg] cannot load certificate "/certs/root_ca.crt": BIO_new_file() failed
```

**Cause**: `rstudio-init` failed to download or install the Root CA, or CA_URL/CA_FINGERPRINT not set.

**Resolution**:
```bash
# Check init container logs
docker logs rstudio_init

# Verify PKI vars in .env
grep -E '^(CA_URL|CA_FINGERPRINT)=' infra-rstudio/.env

# If missing, run configure script
scripts/infra-rstudio/configure_rstudio_pki.sh /path/to/join_pki.env

# Re-run init container manually
docker compose up rstudio-init

# Then restart nginx
docker compose restart nginx-portal
```

---

### 3. RStudio Not Going Healthy — BLAS Thread Starvation

**Symptom**: `rstudio-pet` (or `rstudio-sssd`) container is stuck in `starting` / `unhealthy`. R starts but hangs. High CPU on host.

**Cause**: The default R session opens multiple threads via OpenBLAS. On hosts with many cores, this can create a thread storm that starves other containers or triggers OOM.

**Resolution**:
```bash
# Check current thread limits in .env
grep -E '^(MAX_BLAS|OMP_NUM|OPENBLAS)' infra-rstudio/.env

# Reduce thread counts and redeploy
# In .env:
#   MAX_BLAS_THREADS=4
#   OMP_NUM_THREADS=4
#   OPENBLAS_NUM_THREADS=4

# Check active blas threads inside the container
docker exec rstudio_pet bash -c 'Rscript -e "library(RhpcBLASctl); blas_get_num_procs()"'
```

---

### 4. oauth2-proxy 500 — Missing `oauth2-proxy.cfg`

**Symptom**: Navigating to the portal gives a 500 or redirect loop. `rstudio-oauth2` logs:
```
failed to load configuration: no such file or directory: ./config/oauth2-proxy.cfg
```

**Cause**: The `oidc` profile was activated but `oauth2-proxy.cfg` was never created.

**Resolution**:
```bash
# Create config from template
cp infra-rstudio/config/oauth2-proxy.cfg.example infra-rstudio/config/oauth2-proxy.cfg

# Edit with real Keycloak credentials
$EDITOR infra-rstudio/config/oauth2-proxy.cfg

# Required fields to fill:
#   oidc_issuer_url
#   client_id
#   client_secret
#   redirect_url
#   cookie_secret   (generate: openssl rand -base64 32)

# Restart oauth2-proxy
docker compose restart oauth2-proxy
```

---

### 5. Telemetry API Not Responding

**Symptom**: Portal telemetry strip shows errors. `curl http://localhost:5000/health` returns connection refused.

**Cause**: `telemetry-api` container is not healthy or `docker-socket-proxy` is not ready.

**Resolution**:
```bash
# Check telemetry container status
docker compose ps rstudio_telemetry rstudio_dsp

# Check docker-socket-proxy logs
docker compose logs docker-socket-proxy

# Ensure /var/run/docker.sock exists on host
ls -la /var/run/docker.sock

# Restart in order (dsp first)
docker compose restart docker-socket-proxy
sleep 3
docker compose restart telemetry-api
```

---

### 6. Winbind / Samba Auth Failures

**Symptom**: Using `samba` profile. Users cannot log in. `rstudio-samba` logs:
```
winbind: could not connect to winbindd socket
```

**Cause**: Winbind is not running on the host, or socket path in `.env` is wrong.

**Resolution**:
```bash
# Check Winbind is running on host
systemctl is-active winbind

# Verify socket path
ls /var/run/samba/winbindd/

# Test Winbind from host
wbinfo -t   # Must return: "checking the trust secret for domain ... succeeded"
wbinfo -u   # Should list domain users

# If HOST_WINBINDD_DIR is wrong in .env, correct it and redeploy:
# HOST_WINBINDD_DIR=/correct/path

# Rejoin if trust is broken
net ads testjoin    # or: net rpc testjoin
```

---

### 7. Fingerprint Mismatch — PKI Bootstrapping Fails

**Symptom**: `rstudio-init` fails with:
```
FATAL: Fingerprint MISMATCH
```

**Cause**: `CA_FINGERPRINT` in `.env` does not match the actual Root CA.

**Resolution**:
```bash
# Get the correct fingerprint from PKI host
curl -sf http://192.168.56.10/fingerprint/root_ca.fingerprint

# Or from the CA server itself
curl -sf https://pki.example.com:9000/roots.pem | openssl x509 -noout -fingerprint -sha256

# Update .env
sed -i "s|^CA_FINGERPRINT=.*|CA_FINGERPRINT=<new-fingerprint>|" infra-rstudio/.env

# Re-run init
docker compose up rstudio-init
```

---

## Checking the Audit Trail

All scripts in `scripts/infra-rstudio/` log to stdout with `[INFO]`, `[WARN]`, `[ERROR]` prefixes. To capture a full deployment log:

```bash
scripts/infra-rstudio/deploy_rstudio.sh 2>&1 | tee /var/log/rstudio-deploy-$(date +%Y%m%d).log
```

---

## Operational Maintenance

### TLS Certificate Rotation

If the portal SSL certificates expire, Nginx and TTYD will stop functioning. The ACME/Step-CA enrollment system runs automatic checks at boot.

**Forced certificate rotation** (after compromise or CA re-initialization):

1. Revoke the old certificate on the PKI host (root-CA side)
2. Generate a new access token: `scripts/infra-pki/generate_token.sh`
3. Insert the new token in `.env` (`STEP_TOKEN="..."`)
4. Restart Nginx to trigger the entrypoint ACME script:

```bash
docker compose restart nginx-portal
```

### tmpfs Lifecycle Management

To prevent RAM saturation, container temporary files (`/tmp`) are mapped at runtime using `tmpfs`. This absorbs DataFrame snapshot I/O without hitting disk. Restarting the RStudio container surgically clears the temporary storage:

```bash
docker compose restart rstudio-sssd
```

> **Note**: tmpfs contents are volatile — they are destroyed on container stop/restart. This is by design for security (cache forensic destruction) and performance (zero disk I/O bottleneck).

### OOM / Orphan R Session Cleanup

The host-side script `cleanup_r_orphans.sh` (if configured via crontab) automatically detects `rsession` processes that consume CPU without an active owner. The host terminates them via `SIGTERM`, protecting the `tmpfs` RAM allocation for the RStudio container.

Manual cleanup:

```bash
# List R sessions inside the container
docker exec rstudio_pet ps aux | grep rsession

# Kill a specific orphan (from host, since network_mode: host)
kill -TERM <PID>
```

### Version Updates (Build & Pinning)

Due to the strict version-pinning policy on R/Python dependencies:

```bash
# Rebuild with cache (fast — uses c2d4u binary packages)
docker compose --profile sssd build

# Full rebuild (no cache — when pinned versions change)
docker compose --profile sssd build --no-cache
```

> The `c2d4u` PPA and `bspm` binary packages reduce build time from ~1 hour (source compilation) to minutes.

