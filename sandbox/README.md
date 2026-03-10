# Infra-Iam-PKI Complete Sandbox Environment

This directory provides a **multi-VM**, production-identical sandbox designed to test the full lifecycle of `infra-pki`, `infra-iam`, and `infra-ood` in isolation, each on its own dedicated host — exactly mirroring the target production topology.

---

## Network Topology

| Host       | IP              | Component              | Port                           |
|------------|-----------------|------------------------|--------------------------------|
| `pki-host` | 192.168.56.10   | Step-CA (PKI)          | `:80` (public), `:9000` (API)  |
| `iam-host` | 192.168.56.20   | Keycloak (SSO)         | `:80` (via Caddy proxy)        |
| `ood-host` | 192.168.56.30   | Open OnDemand          | `:80`                          |

Each VM is provisioned on an isolated KVM private network (`192.168.56.0/24`) using libvirt. All hosts communicate inter-VM as they would in production (by IP or DNS), not via shared Docker networks.

---

## Prerequisites

- `vagrant` with the `vagrant-libvirt` provider
- `qemu-kvm` and `libvirt-daemon-system` installed on the host

---

## Getting Started

### 1. Start PKI first (other services depend on it)

```bash
vagrant up pki-host
```

This builds and starts the Step-CA with Postgres backend. The fingerprint of the Root CA is automatically computed and served at `http://192.168.56.10/fingerprint/root_ca.fingerprint`.

### 2. Start IAM

```bash
vagrant up iam-host
```

The provisioner automatically fetches the PKI fingerprint from `pki-host` over the private network, injects it into `.env`, and starts the Keycloak + Caddy stack.

### 3. Start OOD

```bash
vagrant up ood-host
```

The provisioner builds the Open OnDemand image from official Ubuntu Noble 24.04 deb packages (`apt.osc.edu`) and starts the portal.

### 4. Start all at once

```bash
vagrant up
```

> [!IMPORTANT]
> `iam-host` has a built-in retry loop (max 5 min) waiting for `pki-host`'s fingerprint. Ensure `pki-host` is healthy before it times out.

---

## Live Code Updates

After changing any file in `infra-pki`, `infra-iam`, or `infra-ood`:

```bash
vagrant rsync
```

Then restart the relevant compose service inside the VM.

---

## Destroy

```bash
vagrant destroy -f
```

---

## Production Bugs Fixed in Sandbox

| Component     | Bug | Fix |
|---------------|-----|-----|
| `infra-pki`   | `fingerprint` created as empty **directory** instead of file | Changed `fingerprint-writer` to write to `fingerprint/root_ca.fingerprint` |
| `infra-pki`   | `nickfedor/watchtower` image pulled from non-existing repo | Changed to `containrrr/watchtower:1.7.1` |
| `infra-iam`   | Same watchtower image issue | Fixed to `containrrr/watchtower:1.7.1` |
| `infra-iam`   | `iam-init` crashes: `fetch_pki_root.sh` uses relative path that doesn't exist inside container | Hardened to use safe `cd ... || echo '/app'` fallback |
| `infra-ood`   | `osc/ondemand:3.1.0` Docker image never existed on Docker Hub | Replaced with `Dockerfile.ood` using official Ubuntu Noble deb packages from `apt.osc.edu` |
| `infra-pki`   | Caddy served `/fingerprint` as a single path instead of directory subtree | Changed Caddyfile to `/fingerprint/*` |
| `infra-iam`   | IAM received empty `FINGERPRINT` because PKI fingerprint wasn't readable | DNS/HTTP retrieval from PKI host now automatic in Vagrantfile provisioner |
