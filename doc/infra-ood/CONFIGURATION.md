# Open OnDemand Configuration Guide

This guide details the explicit configuration mappings used in `infra-ood` to comply with the project's PRD design, integrating OpenID Connect (OIDC) and custom UI styling.

## 1. Environment Variables (`.env`)

The `infra-ood` stack relies on a `.env` file at its root to securely inject configurations into `docker-compose.yml` during deployment.

| Variable | Description | Example |
| :--- | :--- | :--- |
| `PUID` | Host User ID for permissions mapping | `1000` |
| `PGID` | Host Group ID for permissions mapping | `1000` |
| `OIDC_ENDPOINT` | The public URL of the Keycloak Discovery Endpoint | `https://sso.example.com/realms/master/.well-known/openid-configuration` |
| `OIDC_CLIENT_ID` | The OIDC client identifier configured in Keycloak | `ood-portal` |
| `OIDC_CLIENT_SECRET` | The secure secret matching Keycloak | `suP3rS3cret!123` |
| `CA_URL` | The public endpoint of the `infra-pki` Step-CA | `https://ca.example.com` |
| `FINGERPRINT` | the SHA-256 fingerprint of the remote Root CA | `1234abcd5678...` |

## 2. Portal Configuration (`ood_portal.yml`)

The main configuration file is mapped read-only into `/etc/ood/config/ood_portal.yml`.

### 2.1 OIDC Integration Settings

OOD utilizes the Apache `mod_auth_openidc` plugin. The following configuration defines the security handshake:

```yaml
auth:
  - 'AuthType openidc'
  - 'Require valid-user'

oidc_uri: '/oidc'
oidc_provider_metadata_url: '%{env:OIDC_URI}'
oidc_client_id: '%{env:OIDC_CLIENT_ID}'
oidc_client_secret: '%{env:OIDC_CLIENT_SECRET}'
oidc_remote_user_claim: 'preferred_username'
oidc_scope: 'openid profile email'
```

*Note: We extract `preferred_username` to map directly to Linux user accounts spawned under the PUNs.*

### 2.2 Custom BiGeA Theme Injection

The portal aesthetics are overridden using a custom CSS file mapped via a volume and injected into the portal configuration:

```yaml
custom_css_files:
  - '/public/bigea-theme.css'

dashboard_title: 'Servizi Informatici - Dipartimento BiGeA'
```

To modify the theme colors, update `public/bigea-theme.css` on the host. The changes will reflect dynamically on browser refresh (pending proxy cache). The theme employs `Inter` typography, CSS Variables for `unibo-red`, and explicit `backdrop-filter` rules for glassmorphism.

## 3. Internal Certificate Authority Trust

For `mod_auth_openidc` to validate the TLS certificates returned by the `infra-iam` endpoint, the Open OnDemand Apache server must trust the internal Root CA issued by `infra-pki`.

This is achieved via the `ood-init` container:

1. It executes `fetch_pki_root.sh`, downloading the `.crt` securely over Port 443 based on the `FINGERPRINT`.
2. The downloaded `root_ca.crt` is mapped read-only directly to Red Hat's trust anchor path: `/etc/pki/ca-trust/source/anchors/step-ca.crt`
3. The `ood-portal` entrypoint intercepts the boot sequence, runs `update-ca-trust`, and *then* executes the main Apache binary.
