# Infra-IAM-PKI: Certified Infrastructure & Identity

**Version:** 3.1.0
**Maintainer:** JFS — IT Officer (Funzionario Tecnico Informatico), BiGeA, Università di Bologna

## 1. Project Overview

This repository hosts the strict, **Pessimistic Infrastructure-as-Code (IaC)** for the organization's internal Public Key Infrastructure, Identity Management, HPC Portal, and RStudio compute environment. It enforces Zero-Trust principles, Airgap security, and deterministic compute isolation across Docker Compose and Kubernetes deployment targets.

- **Infra-PKI**: Internal Certificate Authority (`step-ca`) backed by PostgreSQL.
- **Infra-IAM**: Single Sign-On (`Keycloak`) secured by the PKI and integrated with Active Directory.
- **Infra-OOD**: The user-facing HPC gateway built on Open OnDemand, authenticating strictly via Keycloak OIDC.
- **Infra-RStudio**: Precision-engineered RStudio instances with Zero-Trust `oauth2-proxy` sidecars honoring OOD session continuity.
- **AI Constraints**: Built-in AST validation and hard-constraint generation (`.ai/`, `.agents/`) to enforce strict engineering boundaries automatically.

---

## 2. Architecture

```text
[Remote Clients] <---> [Caddy / Nginx Ingress] <---> [Services]
                                    ^
                                    | (TLS via PKI, Sec via IAM)
          +-------------------------+-------------------------+-------------------------+
          |                         |                         |                         |
    [Infra-PKI]               [Infra-IAM]               [Infra-OOD]               [Infra-RStudio]     
   (Step-CA/PG)             (Keycloak/PG/AD)        (Apache/PUN/OIDC)         (RStudio/OAuth2-Proxy)
```

---

## 3. Directory Structure

```plaintext
Infra-Iam-PKI/
├── infra-pki/                  # PKI Service (Docker Compose)
├── infra-iam/                  # IAM Service (Docker Compose)
├── infra-ood/                  # Open OnDemand HPC Portal (Docker Compose)
├── infra-rstudio/              # Zero-Trust RStudio Service (Docker Compose)
├── kubernetes-deploy/          # RKE2 Kubernetes Manifests (Production Parity)
├── sandbox/                    # 4-VM Vagrant Topology for local multi-host testing
├── scripts/                    # Automation Toolkit (enrollment, renewal, patching)
├── doc/                        # Architectural Documentation
├── .ai/                        # Automatic Constraint Generators for AI Coding
└── .agents/                    # Deterministic AI Checklists ("Skills")
```

---

## 4. Deployment Topologies

This repository maintains extreme **Production Parity** across three distinct deployment mechanisms, ensuring zero logical drift whether running locally or in a distributed cluster.

### 4.1 Kubernetes (RKE2)

The standard production target.
See `kubernetes-deploy/README.md` for the sequence of `$ kubectl apply -k` commands utilized to launch the PKI, IAM, OOD, and RStudio isolation namespaces.

### 4.2 Docker Compose (Legacy / Edge)

For standalone or edge environments lacking a K8s control plane.

1. `cd infra-pki && docker compose up -d`
2. `cd infra-iam && docker compose up -d`
3. `cd infra-ood && docker compose up -d`
4. `cd infra-rstudio && docker compose --profile sssd up -d`

### 4.3 Vagrant Sandbox (Local Validation)

To perform destructive networking tests without risking production.
See [doc/SANDBOX_TESTING.md](doc/SANDBOX_TESTING.md).

```bash
cd sandbox && vagrant up
```

---

## 5. Security & Pessimistic Constraints

This repository restricts all code additions using the embedded `.ai/validate.sh` testing pipeline. Before committing, the codebase must pass all **Hard Constraints (HC-01 to HC-14)** defined in `.ai/project.yml`.

Notable constraints actively enforced:

- **Memory/CPU Caps:** Every container limits compute resources (`deploy.resources.limits`) to prevent Linux OOM cascades.
- **Idempotent Automation:** Bash scripts execute deterministic state checks (e.g., checksums) rather than triggering noisy container restarts blindly.
- **Airgap / Zero-Trust:** UI Themes (`bigea-theme.css`) are strictly forbidden from executing outbound tracking calls to external CDNs (like Google Fonts).
- **Dependency Sandboxing:** Ephemeral utilities (`iam-init`, `fetch-pki-certs`) operate strictly as explicit sidecars passing data securely rather than mounting root `.env` files indiscriminately.

---

## 6. Documentation Index

- **Infra-PKI**: [Overview](doc/infra-pki/OVERVIEW.md) | [Deploy](doc/infra-pki/DEPLOY.md)
- **Infra-IAM**: [Overview](doc/infra-iam/OVERVIEW.md) | [Deploy](doc/infra-iam/DEPLOY.md)
- **Infra-OOD**: [Overview](doc/infra-ood/OVERVIEW.md)
- **Infra-RStudio**: [Overview](doc/infra-rstudio/OVERVIEW.md) | [Deploy](doc/infra-rstudio/DEPLOY.md) | [Configuration](doc/infra-rstudio/CONFIGURATION.md) | [Security](doc/infra-rstudio/SECURITY.md) | [Troubleshooting](doc/infra-rstudio/TROUBLESHOOTING.md)
- **Architecture**:
  - [Sandbox Testing Guide](doc/SANDBOX_TESTING.md)
  - [AI Agent Management Constraints](doc/AI_AGENT_MANAGEMENT.md)

---
> Generated & Maintained by the Antigravity Team
