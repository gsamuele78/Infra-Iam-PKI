# Integrating TrueNAS SCALE 25.04 with Internal Step-CA

This guide details how to configure **TrueNAS SCALE (v25.04)** to issue certificates from your internal **Step-CA** instance.

## Prerequisites

- **Step-CA IP**: `172.30.119.221`
- **TrueNAS IP**: `172.30.119.223`
- **Root CA URL**: `http://172.30.119.221/certs/root_ca.crt`
- **ACME Directory**: `https://172.30.119.221:9000/acme/acme/directory`
- **TrueNAS Hostname**: `truenas.internal` (Example - Replace with your actual FQDN)

> [!IMPORTANT]
> Since this is an internal setup without public DNS, and TrueNAS UI often defaults to DNS-01 challenges, we will use the **HTTP-01** challenge via a manual script (`acme.sh`) on TrueNAS.

## Phase 1: Establish System-Wide Trust

TrueNAS must trust your internal CA to communicate with the ACME server.

1. **Download Root CA**:
    Download the root certificate from `http://172.30.119.221/certs/root_ca.crt` to your computer.

2. **Import to TrueNAS**:
    - Navigate to **Credentials > Certificates > Certificate Authorities**.
    - Click **Add** and select **Type: Import CA**.
    - **Name**: `Internal-Step-Root`
    - **Certificate**: Paste the content of `root_ca.crt`.
    - **Add to Trusted Store**: **CHECK THIS BOX**.
    - Click **Save**.

## Phase 2: DNS Resolution (Crucial for HTTP-01)

For the HTTP-01 challenge to work, the **Step-CA server must be able to resolve the TrueNAS hostname** to its IP (`172.30.119.223`).

1. **On Step-CA Server**:
    Ensure `/etc/hosts` or your internal DNS server maps the TrueNAS hostname.

    ```bash
    # On the host running docker/step-ca (or inside the step-ca container)
    echo "172.30.119.223 truenas.internal" >> /etc/hosts
    ```

    *Verification*: From the Step-CA container, try `ping truenas.internal`.

## Phase 3: Issue Certificate via `acme.sh` (Manual Method)

Since the TrueNAS GUI limitations often prevent internal HTTP-01 validation, we will use the built-in `acme.sh` client via SSH to perform authentication and installation.

1. **SSH into TrueNAS**:

    ```bash
    ssh admin@172.30.119.223
    sudo -i
    ```

2. **Register Account**:
    Register with your internal Step-CA.

    ```bash
    acme.sh --register-account \
    --server https://172.30.119.221:9000/acme/acme/directory \
    --email admin@truenas.internal
    # If SSL error: append --ca-bundle /etc/ssl/certs/ca-certificates.crt (verify CA is in trust store)
    ```

3. **Issue Certificate (Webroot/Standalone Mode)**:
    Since TrueNAS redirects port 80 to 443, use `standalone` mode on a different port if possible, or momentarily stop the redirect. However, `acme.sh` allows specifying a port for standalone mode.

    ```bash
    # Try standalone mode (requires port 80 to be open/forwarded or checking if acme.sh can bind)
    # If TrueNAS binds port 80, you might need to use --webroot /var/db/system/webui/ (check path)
    
    acme.sh --issue --standalone \
    -d truenas.internal \
    --server https://172.30.119.221:9000/acme/acme/directory \
    --httpport 80
    ```

4. **Install Certificate to TrueNAS API**:
    Once issued, upload it to TrueNAS using the deploy hook.

    ```bash
    # Generate API Key in TrueNAS UI: Settings > API Keys
    export TRUENAS_API_KEY="<YOUR_API_KEY_FROM_UI>"
    export TRUENAS_HTTP_INSECURE_SKIP_VERIFY=1
    
    acme.sh --deploy -d truenas.internal \
    --deploy-hook truenas
    ```

## Summary

1. **Import Root CA** into TrueNAS Trusted Store.
2. **Update Step-CA's `/etc/hosts`** so it can find TrueNAS (for verification).
3. **Run `acme.sh`** on TrueNAS to request the cert.
4. **Deploy** using the `truenas` hook to apply it to the UI.
