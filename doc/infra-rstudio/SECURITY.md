# Infra-RStudio: Security Model

This document describes the defense-in-depth security architecture of the containerized RStudio deployment. The design follows Pessimistic System Engineering principles — every input is treated as malicious until proven otherwise by server-side validation.

---

## 1. Container Defense Boundaries

### CPU/Memory Constraints & Livelock Prevention

To prevent DoS attacks or host resource exhaustion (OOM Kernel Panic):

- The `docker-compose.yml` enforces coercive `deploy.resources.limits` blocks (e.g., 16 cores on Ollama, up to 60GB on RStudio for large geospatial workloads).
- The `tmpfs` directive replaces standard mounts on the application's vectorial `/tmp`. This not only prevents storage runout (100% inode exhaustion) but also forensically destroys package caches on every restart.

### Ephemeral Configuration & File System Isolation

No configuration file (e.g., `Rprofile.site`, `rserver.conf`) is permanently stored on disk.

- At boot, the entrypoint scripts use `mktemp` to assemble configuration from `.env` variables.
- This prevents race conditions, symlink attacks, and type-squatting — common risks in multi-layer filesystem containers — by writing to UUID-randomized temporary files before atomic mapping.
- The entrypoint uses `process_template()` from the shared utility library for all template rendering.

---

## 2. Network Topology & Edge Security

### Host-Only AI and Telemetry Bindings

All secondary microservices (Ollama, Telemetry FastAPI, RStudio RPC) are segregated from the public LAN:

- Expose directives force the loopback address (`127.0.0.1`) in runtime ENV, e.g., `OLLAMA_HOST=127.0.0.1:11434`. No port crosses the Nginx reverse proxy boundary.
- This mitigates access bypass scenarios even if the host's `iptables` firewall collapses.

### Why `network_mode: host`

The pet container and its auth sidecars use `network_mode: host`. This is a **documented architectural exception** (see [OVERVIEW.md](OVERVIEW.md) § "Why network_mode: host").

**Reason**: SSSD and Winbind communicate through Unix domain sockets (`/var/run/sssd/`, `/var/run/samba/`) that exist on the host. The containers must share the host network namespace to resolve Kerberos KDC and LDAP/AD endpoints at host-configured addresses. No other stack in this project may use `network_mode: host`.

---

## 3. Nginx Gateway Security

### Strict Gateway & CSRF Verification

- Auth routes (e.g., `/auth-sign-out`) for the RStudio RPC do not support optimistic JSON fallbacks; they require strict CSRF token validation injected only by the original Web Portal (Referer validation).
- TTY buffers (`client_max_body_size`, `proxy_buffers`) are reduced to the minimum necessary to absorb WebSocket payloads while mitigating "Slowloris" stack floods.

### Routing Architecture

All traffic enters via Nginx (`:443`/`:80`) and is dispatched to the host loopback via native `upstream` directives:

| Route | Target | Protocol |
| :--- | :--- | :--- |
| `/` | Portal HTML (static, boot-generated) | HTTP |
| `/rstudio-inner/` | RStudio Server `:8787` | HTTP + WebSocket |
| `/api/telemetry/` | Python Uvicorn API (localhost) | HTTP |
| `/files/` & `/status/` | Nextcloud / Grafana iframe modules | HTTP |
| `/terminal/` | TTYD WebSocket terminal | TCP/WebSocket |

### Enterprise Security Headers (Phase 3 Hardening)

The following headers are injected programmatically by `entrypoint_nginx.sh` into the root location:

- `Strict-Transport-Security` (HSTS)
- `X-XSS-Protection`
- `X-Content-Type-Options: nosniff`
- `Content-Security-Policy` (restrictive)

### Timeout Coordination

Nginx session timeouts are synchronized with RStudio (`RSESSION_TIMEOUT_MINUTES`), preventing ghosted client connections (socket leakage prevention). Buffer sizes are incrementally tuned for JSON-RPC payloads from Shiny apps without exposing OOM vulnerabilities in the Nginx master process.

---

## 4. PKI Trust Model

The container autonomously imports Root of Trust (Step-CA or AD-CS) at startup. The `manage_pki_trust.sh` script (v2.0) uses mandatory SHA256 fingerprint verification before installing the Root CA — blocking Man-in-the-Middle attacks within the institutional DMZ.

Trust chain bootstrap:
1. `rstudio-init` starts first (ephemeral init container)
2. Calls `manage_pki_trust.sh CA_URL CA_FINGERPRINT` with mandatory fingerprint verification
3. Root CA installed into system trust store AND shared `/certs` volume
4. `nginx-portal` and `rstudio-pet` read certs from `/certs`
5. R packages (`httr`, `curl`) can complete TLS chains to internal HTTPS services

---

## 5. Pessimistic Initialization

### Blocking Auth Verification

The optimistic startup approach has been eliminated. `entrypoint_rstudio.sh` includes a blocking loop (`until wbinfo -p` or `getent passwd`) that halts the engine until the host-side UNIX AD/PAM socket responds — preventing critical boot race conditions where RStudio starts before authentication is available.

### Strict Capabilities Drop

The RStudio service has explicitly revoked the Linux `SYS_CHROOT` capability (`cap_drop: ["SYS_CHROOT"]`), reducing the attack surface from within the container toward the hypervisor.

### Engine Starvation Limits

Resource allocation for `ollama-ai` is clamped to 2.5 cores and bounded memory, preventing "Noisy Neighbor" resource exhaustion scenarios where AI inference consumes all host CPU.

---

## 6. Software Lifecycle Reliability

- **R Package Installation**: Uses `r-cran-bspm` to disable RCE-vulnerable source compilation in favor of digitally signed binary packages from the c2d4u apt repository. Falls back to parallel compilation with `Ncpus = detectCores()` if binaries are unavailable.
- **Python Dependencies**: FastAPI, Uvicorn, and Pydantic are version-pinned during `pip install`. Phantom upstream dependency changes cannot silently compromise Docker images built months after code authoring.
- **Portal UI**: JavaScript pre-loading uses `Promise.race()` with an artificial timeout, degrading gracefully to a visible error fallback instead of infinite loading spinners when a silent backend fails to respond.
