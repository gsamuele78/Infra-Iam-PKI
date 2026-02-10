# Securing Nextcloud App on TrueNAS SCALE with Step-CA

This guide explains how to issue and apply a certificate for a **Nextcloud App** running on TrueNAS SCALE with a dedicated IP (`172.30.119.150`).

## Prerequisites

- **Step-CA IP**: `172.30.119.221`
- **TrueNAS Management IP**: `172.30.119.223`
- **Nextcloud App IP**: `172.30.119.150`
- **Domain**: `nextcloud.internal` (Example)

## Strategy: Centralized Certificate Management (Recommended)

Even though Nextcloud has its own IP, the most robust way to manage certificates in TrueNAS SCALE is to issue them on the TrueNAS host itself and then assign them to the App.

This requires a specific workflow for internal ACME validation:

1. **Validation**: Step-CA talks to **TrueNAS Host** (`.223`) on port 80 to verify ownership.
2. **Usage**: Once issued, TrueNAS pushes the cert to the **Nextcloud App** (`.150`).

> [!WARNING]
> DO NOT try to resolve `nextcloud.internal` to the App IP (`.150`) on the Step-CA server for validation, unless you are running `acme.sh` *inside* the Nextcloud container (which is ephemeral and harder to maintain).
>
> **The Step-CA must resolve the domain to the TrueNAS Host IP (`.223`) for the validation step.**

## Step 1: Update Step-CA DNS for Validation

For the HTTP-01 challenge to succeed, Step-CA must connect to the machine running the ACME client (TrueNAS Host).

1. **On Step-CA Server**:
    Map the Nextcloud domain to the **TrueNAS Management IP** (`172.30.119.223`).

    ```bash
    # /etc/hosts on Step-CA container/host
    172.30.119.223 nextcloud.internal
    ```

    *Why?* Because `acme.sh` runs on the TrueNAS host OS, not inside the app container.

## Step 2: Issue Certificate via `acme.sh` on TrueNAS

1. SSH into TrueNAS (`172.30.119.223`):

    ```bash
    ssh admin@172.30.119.223
    sudo -i
    ```

2. Run `acme.sh` in Standalone Mode:
    You need to temporarily use port 80 on the TrueNAS host.

    ```bash
    acme.sh --issue --standalone \
    -d nextcloud.internal \
    --server https://172.30.119.221:9000/acme/acme/directory \
    --httpport 80
    ```

    *Success Reference*: `Cert success.`

3. Deploy to TrueNAS UI:
    This makes the certificate available in the TrueNAS "Certificates" list.

    ```bash
    export TRUENAS_API_KEY="<YOUR_KEY>"
    export TRUENAS_HTTP_INSECURE_SKIP_VERIFY=1
    
    acme.sh --deploy -d nextcloud.internal --deploy-hook truenas
    ```

## Step 3: Configure Nextcloud App

Now that the valid certificate is in TrueNAS, assign it to the App.

1. Go to **Apps** > **Nextcloud** > **Edit**.
2. Find the **Ingress** or **Network** section (depends on Chart version detailed implementation).
    - If using **Traefik/Ingress**: Ensure the Ingress uses the secret name containing your new cert.
    - If using **Standard App Config**: Look for "Certificate" field. Select the newly imported `nextcloud.internal` certificate.
3. **Save/Update** the App.

## Step 4: Client DNS (The Switch)

Now that the certificate is installed:

- **Step-CA** sees `nextcloud.internal` -> `172.30.119.223` (for renewals).
- **Your PC/Users** must see `nextcloud.internal` -> `172.30.119.150` (Nextcloud App IP).

Ensure your network DNS (e.g., Pi-hole, Windows DNS) points users to the **App IP (`.150`)**.

> [!NOTE]
> When `acme.sh` renews the cert (automagically via cron), it will spin up port 80 on the Host (`.223`). Step-CA will connect to `.223` (thanks to its `/etc/hosts`), validate, and then the hook will update the cert in TrueNAS, which should propagate to the App.
