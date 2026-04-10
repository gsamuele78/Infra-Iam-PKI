# RStudio (Infra-RStudio) Integration with Step-CA

This guide explains how to secure the RStudio deployment using certificates issued by the internal **Infra-PKI** (Step-CA).

## Architecture

- **PKI Host**: Runs `infra-pki` (Step-CA) at e.g., `192.168.56.10`.
- **RStudio Host**: Runs `infra-rstudio` (RStudio Server + Nginx + auth sidecars) at e.g., `192.168.56.40`.

The integration uses a **One-Time Token (OTT)** generated on the PKI Host to enroll the RStudio Host securely. Additionally, the RStudio stack bootstraps Root CA trust automatically via the `rstudio-init` ephemeral container.

## Workflow

### 1. On PKI Host: Generate Token & Join File

Login to the server running `infra-pki`.
Run the token generation script:

```bash
cd /opt/docker/Infra-Iam-PKI/
sudo scripts/infra-pki/generate_token.sh
```

- **Hostname**: Enter the FQDN of the RStudio host (must match `HOST_DOMAIN` in `infra-rstudio/.env`)
- **Output**: A `infra-rstudio_join_pki.env` file containing `CA_URL` and `CA_FINGERPRINT`

### 2. On RStudio Host: Configure PKI Trust

Transfer the join file to the RStudio host and run:

```bash
cd /opt/docker/Infra-Iam-PKI/
scripts/infra-rstudio/configure_rstudio_pki.sh /path/to/infra-rstudio_join_pki.env
```

This injects `CA_URL` and `CA_FINGERPRINT` into `infra-rstudio/.env`.

### 3. On RStudio Host: Deploy

```bash
scripts/infra-rstudio/deploy_rstudio.sh
```

The deployment script will:
1. Start `rstudio-init` (ephemeral container) which fetches Root CA from `CA_URL`, verifies it against `CA_FINGERPRINT`, and installs it to the shared `/certs` volume.
2. Start `nginx-portal` which reads the Root CA from `/certs` for upstream TLS verification.
3. If `STEP_TOKEN` is set, Nginx will also enroll its own TLS certificate via the Step-CA ACME endpoint.

## Trust Verification

After deployment, verify the trust chain:

```bash
# Check Root CA is installed in containers
docker exec rstudio_pet ls -l /usr/local/share/ca-certificates/step_root_ca.crt

# Verify Nginx is serving a valid certificate
curl -sf --cacert infra-rstudio/certs/root_ca.crt https://${HOST_DOMAIN}

# Check R can validate internal HTTPS endpoints
docker exec rstudio_pet Rscript -e 'httr::GET("https://keycloak.internal/health")'
```

## Automatic Renewal

- After initial enrollment, the Nginx certificate is used for authentication on subsequent renewals.
- The `entrypoint_nginx.sh` checks certificate validity at every container start.
- No further tokens are required for renewals — only for first-time enrollment or after full CA re-initialization.
