# Troubleshooting Guide

## 1. Common Issues

### 1.1 "Connection Refused" on Port 9000

* **Cause**: Caddy is not running, or IP is blocked.
* **Check**:
    1. Is Caddy container up? `docker compose ps`
    2. Check Caddy logs: `docker compose logs caddy`
    3. Verify your IP is in `ALLOWED_IPS` in `.env`.

    4. Check Caddy logs: `docker compose logs caddy`
    5. Verify your IP is in `ALLOWED_IPS` in `.env`.
    6. **Health Check Failure**: If `deploy_pki.sh` reports `✗ CA health endpoint check failed`, ensure the **pinned pki-net bridge subnet** (`172.28.100.0/24`) is in `ALLOWED_IPS`. The script runs from the host but connects via the gateway.

### 1.2 Health Code `000` on :9000 — Docker Subnet Drift After Reset

> [!IMPORTANT]
> This is NOT a certificate problem. `curl -k` never reaches the TLS handshake:
> Caddy L4 drops the TCP connection because the source IP is not allowlisted.

* **Symptom matrix** (the tell-tale combination):

  | Check | Result |
  |---|---|
  | `docker compose ps` | all containers HEALTHY |
  | `nc -z localhost 9000` | **succeeds** (Caddy accepts TCP, then drops) |
  | `curl -sk https://localhost:9000/health` | **fails**, code `000` |
  | `docker exec step-ca step ca health` | `ok` (bypasses Caddy) |

* **Cause**: Docker assigns custom-network subnets sequentially (`172.18.x`,
  `172.19.x`, ...). After `reset_pki.sh` (or any `docker compose down` that
  recreates `pki-net`), the network can land on a **different subnet** than the
  one listed in `ALLOWED_IPS`. Connections from the host arrive at Caddy with
  the **bridge gateway** as source IP (never `127.0.0.1`), so Caddy L4
  silently drops everything host-originated.
* **Diagnose** (30 seconds):

  ```bash
  # 1. What subnet did pki-net actually get?
  docker network inspect pki-net --format '{{(index .IPAM.Config 0).Subnet}} gw={{(index .IPAM.Config 0).Gateway}}'

  # 2. Prove step-ca is fine when Caddy is bypassed (from inside pki-net)
  docker run --rm --network pki-net curlimages/curl:8.11.1 -sk https://step-ca:9000/health

  # 3. Compare with the allowlist
  grep ^ALLOWED_IPS infra-pki/.env
  ```

  If the subnet from (1) is missing from (3) while (2) returns
  `{"status":"ok"}`, this is your problem.
* **Fix (permanent)**: the subnet is now **pinned** in
  `infra-pki/docker-compose.yml` (`ipam: subnet: 172.28.100.0/24`), so it can
  no longer drift. Ensure `172.28.100.0/24` is in `ALLOWED_IPS`, then:

  ```bash
  cd infra-pki
  docker compose down   # network must be RECREATED — 'restart' is not enough
  docker compose up -d
  ../scripts/infra-pki/verify_pki.sh
  ```

  `down` does not touch `step_data/`/`db_data/` (bind mounts): CA identity,
  root certificate and fingerprint are preserved.
* **Guardrails**: `verify_pki.sh` and `validate_config.sh` now auto-detect the
  actual pki-net subnet and flag any mismatch with `ALLOWED_IPS` explicitly.

### 1.3 Database Connection Errors

* **Logs**: `step-ca` logs show `pq: password authentication failed` or `dial tcp: lookup postgres...`
* **Fix**:
  * Ensure `POSTGRES_PASSWORD` matches in `.env`.
  * If you changed the password *after* initialization, you must delete `db_data` volume to reset the DB, or manually update the postgres user.

  * Ensure `POSTGRES_PASSWORD` matches in `.env`.
  * If you changed the password *after* initialization, you must delete `db_data` volume to reset the DB, or manually update the postgres user.
  * **DSN Parsing Error**: If logs show `cannot parse postgresql://...`, it usually means special characters in the password. This is now automatically handled by `patch_ca_config.sh` which URL-encodes credentials. Ensure the patch script is running (check entrypoint logs).

### 1.4 "Badger" Database Warnings

* **Context**: If you see references to BadgerDB in logs.
* **Fix**: Confirm `step-ca` env vars `PG*` (PGHOST, etc.) are set. `step-ca` defaults to Badger if Postgres config is missing.

### 1.5 SSH Host Bootstrap Fails

* **Error**: `provisioner not found` or authentication failure.
* **Fix**:
  * Ensure `SSH_HOST_PROVISIONER_PASSWORD` is set in `.env`.
  * Check `setup` container logs to see if "Adding dedicated JWK provisioner..." ran successfully.
  * Verify provisioner list: `docker compose exec step-ca step ca provisioner list`

## 2. Diagnostic Commands

### Check CA Status

```bash
docker compose exec step-ca step ca health
```

### List Provisioners

```bash
docker compose exec step-ca step ca provisioner list
```

### View Logs

```bash
# tail all logs
docker compose logs -f
# specific service
docker compose logs -f step-ca
```
