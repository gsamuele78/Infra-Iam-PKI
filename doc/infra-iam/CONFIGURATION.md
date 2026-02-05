# Configuration Reference

The `infra-iam` stack is configured primarily via the `.env` file.

## Environment Variables

### General

| Variable | Description | Example |
| :--- | :--- | :--- |
| `PUID` / `PGID` | User/Group ID for file permissions | `1000` |
| `DOMAIN_SSO` | Public DNS for Keycloak | `sso.example.com` |

### Keycloak & Database

| Variable | Description | Example |
| :--- | :--- | :--- |
| `KC_ADMIN_PASSWORD` | Password for the `admin` user | `change_me...` |
| `DB_PASSWORD` | Password for the PostgreSQL DB | `change_me...` |

### PKI Integration

| Variable | Description |
| :--- | :--- |
| `CA_URL` | URL of the internal Step-CA (e.g., `https://ca.example.com:9000`) |
| `FINGERPRINT` | SHA256 Fingerprint of the Root CA |

### Active Directory

| Variable | Description | Example |
| :--- | :--- | :--- |
| `AD_HOST` | Hostname of the Domain Controller | `ad.example.com` |
| `AD_PORT` | LDAPS port | `636` |

## Scripts

### `configure_iam_pki.sh`

**Location**: `scripts/infra-iam/configure_iam_pki.sh`
**Usage**: `./configure_iam_pki.sh <config_file>`
**Purpose**: Automates the setup of `CA_URL` and `FINGERPRINT` in `.env`.
**Input**: Consumes the output file from `infra-pki/scripts/infra-pki/generate_token.sh`.

### `fetch_pki_root.sh`

**Location**: `scripts/infra-iam/fetch_pki_root.sh` (Mounted inside container)
**Purpose**: Internal script used by the `setup` container to securely download the Root CA.

### `fetch_ad_cert.sh`

**Location**: `scripts/infra-iam/fetch_ad_cert.sh`
**Purpose**: Fetches the AD Certificate Chain to enable LDAPS trust. Called automatically by `setup`.
