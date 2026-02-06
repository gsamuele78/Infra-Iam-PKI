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
    6. **Health Check Failure**: If `deploy_pki.sh` reports `✗ CA health endpoint check failed`, ensure the **Docker Bridge Network** (usually `172.18.0.0/16`) is in `ALLOWED_IPS`. The script runs from the host but connects via the gateway.

### 1.2 Database Connection Errors

* **Logs**: `step-ca` logs show `pq: password authentication failed` or `dial tcp: lookup postgres...`
* **Fix**:
  * Ensure `POSTGRES_PASSWORD` matches in `.env`.
  * If you changed the password *after* initialization, you must delete `db_data` volume to reset the DB, or manually update the postgres user.

  * Ensure `POSTGRES_PASSWORD` matches in `.env`.
  * If you changed the password *after* initialization, you must delete `db_data` volume to reset the DB, or manually update the postgres user.
  * **DSN Parsing Error**: If logs show `cannot parse postgresql://...`, it usually means special characters in the password. This is now automatically handled by `patch_ca_config.sh` which URL-encodes credentials. Ensure the patch script is running (check entrypoint logs).

### 1.3 "Badger" Database Warnings

* **Context**: If you see references to BadgerDB in logs.
* **Fix**: Confirm `step-ca` env vars `PG*` (PGHOST, etc.) are set. `step-ca` defaults to Badger if Postgres config is missing.

### 1.4 SSH Host Bootstrap Fails

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
