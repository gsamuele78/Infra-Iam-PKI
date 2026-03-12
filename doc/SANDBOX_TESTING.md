# Infra-IAM-PKI Sandbox Testing Guide

This project utilizes a rigorous, multi-host Vagrant sandbox to simulate a distributed production network locally. This ensures that network boundaries, firewall rules, and cross-host communication protocols are explicitly validated before deployment.

## Topology & Architecture

The sandbox uses `libvirt/KVM` and provisions four isolated Virtual Machines on a private network (`192.168.56.0/24`).

1. **`pki-host` (192.168.56.10)**: The Zero-Trust Root CA (`step-ca`). This is the foundation of trust.
2. **`iam-host` (192.168.56.20)**: Keycloak Identity Management.
3. **`ood-host` (192.168.56.30)**: Open OnDemand HPC Portal.
4. **`rstudio-host` (192.168.56.40)**: RStudio Server with a Zero-Trust `oauth2-proxy` sidecar.

## The Principle of "Production Parity"

A core pessimistic engineering constraint is that **the Sandbox must run the Production code**.

- `pki-host` boots directly from `infra-pki/docker-compose.yml`. There is no "sandbox override" for PKI.
- `iam-host`, `ood-host`, and `rstudio-host` use `sandbox/iam-sandbox.yml`, `sandbox/ood-sandbox.yml`, and `sandbox/rstudio-sandbox.yml` primarily to inject the `192.168.56.x` IPs into the environment variables, but they build the exact same `Dockerfile`s and use the exact same deployment configuration as production.

## Testing Protocol

To execute a clean test:

1. **Destroy old state**: `cd sandbox && vagrant destroy -f`
2. **Boot PKI First**: `vagrant up pki-host`. The PKI CA must be online to generate the root fingerprint.
3. **Boot Dependents**: `vagrant up iam-host ood-host rstudio-host`. Vagrant triggers automatically fetch the new CA fingerprint from `pki-host` and inject it into the dependents' `.env` files.
4. **Iterate**: Make code changes locally, then run `vagrant rsync` to instantly push changes to all VMs. SSH into the target VM (`vagrant ssh ood-host`) and run `docker compose restart`.

## E2E SSO Validation

The sandbox includes an automated script (`sandbox/ood-test-sso-flow.sh`) that simulates a full, non-optimistic browser authentication flow. It manually passes OIDC tokens and cookies via `curl` to guarantee the Keycloak-to-OOD token exchange functions perfectly within the sandbox network constraints, and it further verifies seamless implicit SSO authentication directly flowing into the RStudio `oauth2-proxy`.
