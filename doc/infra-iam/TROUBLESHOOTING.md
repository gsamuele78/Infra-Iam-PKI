# Troubleshooting

## Initialization Issues

### Certificate Fetch Failure

**Symptom**: `setup` container exits with error code.
**Check**:

1. Logs: `docker compose logs setup`
2. Is `CA_URL` reachable from inside the container?
3. Is `FINGERPRINT` correct?

### Trust Issues with AD

**Symptom**: Keycloak cannot connect to LDAP (`PKIX path building failed`).
**Solution**:

1. Verify `fetch_ad_cert.sh` successfully retrieved the cert:

    ```bash
    ls -l infra-iam/certs/ad_root_ca.crt
    ```

2. Ensure Keycloak volume mount maps this file to `/etc/x509/ca/`.

## Runtime Issues

### 502 Bad Gateway (Caddy)

**Cause**: Keycloak is not yet ready or unreachable.
**Check**:

1. Keycloak health: `docker compose logs keycloak`
2. Wait a few minutes on first boot for DB initialization.

### Database Connection Failed

**Check**:

1. Ensure `db` service is healthy.
2. Verify `DB_PASSWORD` matches in `.env` and was not changed after the volume was created.
