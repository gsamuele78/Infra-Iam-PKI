# Generic Host/Webserver Integration with Internal Step-CA

This guide explains how to configure a generic Linux server (hosting Nginx, Apache, or other services) to issue certificates from your internal Step-CA.

## Prerequisites

- **Step-CA IP**: `172.30.119.221`
- **Your Webserver IP**: `<YOUR_SERVER_IP>`
- **Root CA URL**: `http://172.30.119.221/certs/root_ca.crt`
- **ACME Directory**: `https://172.30.119.221:9000/acme/acme/directory`
- **Domain Name**: `<your-domain.internal>`

## Phase 1: Trust the Root CA

Your server must trust the Step-CA Root certificate to communicate with the ACME directory.

### Debian/Ubuntu

```bash
curl -o /usr/local/share/ca-certificates/step-root-ca.crt http://172.30.119.221/certs/root_ca.crt
update-ca-certificates
```

### RHEL/CentOS

```bash
curl -o /etc/pki/ca-trust/source/anchors/step-root-ca.crt http://172.30.119.221/certs/root_ca.crt
update-ca-trust
```

## Phase 2: Ensure DNS Resolution (Crucial)

For the **HTTP-01** challenge, the Step-CA server must be able to connect to *your* webserver using its domain name.

1. **Check Step-CA Resolution**:
    Ensure the Step-CA container/host can resolve `<your-domain.internal>` to `<YOUR_SERVER_IP>`.

    *If you don't have a central internal DNS:*
    Add an entry to `/etc/hosts` **on the Step-CA server**:

    ```bash
    # On Step-CA Host
    <YOUR_SERVER_IP> <your-domain.internal>
    ```

## Phase 3: Issue Certificate

You can use standard ACME clients like `certbot` or `acme.sh`.

### Option A: Using Certbot (Recommended for Nginx/Apache)

1. **Install Certbot**:

    ```bash
    apt-get install certbot python3-certbot-nginx # (or apache)
    ```

2. **Request Certificate**:

    ```bash
    certbot --nginx \
      --server https://172.30.119.221:9000/acme/acme/directory \
      -d <your-domain.internal> \
      --register-unsafely-without-email
    ```

    *Note: The `--nginx` plugin automatically configures your webserver.*

### Option B: Using acme.sh (Lightweight/Standalone)

1. **Install acme.sh**:

    ```bash
    curl https://get.acme.sh | sh
    source ~/.bashrc
    ```

2. **Request Certificate**:

    ```bash
    acme.sh --issue --standalone \
      -d <your-domain.internal> \
      --server https://172.30.119.221:9000/acme/acme/directory \
      --httpport 80
    ```

## Phase 4: Automation

- **Certbot**: Automatically installs a systemd timer or cron job.
- **acme.sh**: Automatically installs a cron job.

Both clients will renew certificates automatically. **Ensure the Step-CA `/etc/hosts` entry remains valid** if IPs change!
