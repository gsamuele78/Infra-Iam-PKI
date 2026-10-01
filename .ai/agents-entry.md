# AGENTS.md

Instructions for coding agents working in this repo. The full context
(architecture, boot sequences, script catalog) is in
[.ai/agents.md](.ai/agents.md); humans start at [README.md](README.md) and
[CONTRIBUTING.md](CONTRIBUTING.md).

## What this repo is

Infrastructure as code for an internal PKI (step-ca), SSO (Keycloak with AD
federation), an Open OnDemand portal and RStudio Server, one Docker Compose
stack per host. Kubernetes manifests exist but are experimental.

## Layout

| Path | Contents | Deployed? |
| --- | --- | --- |
| `infra-pki/` | step-ca + PostgreSQL + Caddy L4 stack | yes (CA host) |
| `infra-iam/` | Keycloak + PostgreSQL + Caddy L7 + renewer | yes (IAM host) |
| `infra-ood/` | Open OnDemand portal | yes (OOD host) |
| `infra-rstudio/` | RStudio stack, **vendored from R-studioConf** (`UPSTREAM.lock`) | yes (RStudio host) |
| `scripts/` | operator scripts: deploy, reset, backup, enrollment, trust | yes (run on hosts) |
| `kubernetes-deploy/` | RKE2 manifests (`rstudio/` is vendored) | experimental |
| `sandbox/` | Vagrant/libvirt lab, lab-only env files | **never** |
| `doc/` | operator documentation, plans | read by operators |
| `.ai/` | constraint source (`project.yml`), validator, generator, hooks | no |

## Rules

Hard rules (from `.ai/project.yml`; `.ai/validate.sh` enforces them):

<!-- HARD_RULES -->

- Never edit a vendored RStudio file (`infra-rstudio/`, `kubernetes-deploy/rstudio/`,
  the files listed in `infra-rstudio/UPSTREAM.lock`). Fix it in R-studioConf, then
  run `scripts/infra-rstudio/sync_rstudioconf.sh --update`.
- Fix bugs in the deployed files. Never work around a product bug inside `sandbox/`.
- Never copy sandbox values (`.env.sandbox`, `192.168.56.*`) into production files.
- Add a `CHANGELOG.md` entry under `[Unreleased]` for every user-visible change,
  with upgrade steps when an operator must act.
- Don't commit, tag, release or push without being asked.

## Before you say "done"

```bash
make lint        # shellcheck + .ai/validate.sh + generate.sh --check + vendor check
make validate    # docker compose config for the four stacks
make test        # not implemented yet: exits 1 on purpose (ALIGNMENT-PLAN Phase 5)
```

Then run the sandbox tier for the stack you touched (`doc/SANDBOX_TESTING.md`).
If you couldn't run it, say so. Don't report it as passed.

## Gotchas

- Caddy on the PKI host is a **layer 4** proxy: `ALLOWED_IPS` must contain the
  Docker bridge CIDR (`172.28.100.0/24`), or host-side scripts are dropped silently.
- `generate_token.sh` writes `<host>_join_pki.env`, which `configure_iam_pki.sh`
  parses with `grep | cut`. Changing one breaks the other.
- Scripts call `docker compose exec -T` (no TTY): `-it` breaks cron, CI and init.
- `infra-rstudio` is the only stack on `network_mode: host` (SSSD/Winbind socket
  passthrough). Its docker-socket-proxy is the exception to the exception: bridge,
  published on `127.0.0.1` only.
- `step ca certificate` and `step ca renew` have no `--fingerprint` flag. Trust
  comes from `--root` with a root file fetched by `step ca root --fingerprint`.
