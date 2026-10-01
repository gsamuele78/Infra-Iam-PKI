# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/). The plan that drives
the 3.x → 4.x releases is
[docs/plan/ALIGNMENT-PLAN.md](docs/plan/ALIGNMENT-PLAN.md).

## [Unreleased]

## [3.1.0] - 2026-10-01

Baseline release: the first tagged state of the repo, after the
security clean-up of the alignment plan's Phase 0. Earlier commits carry
no version.

### Security

- Untracked files that held secrets or machine keys:
  `sandbox/.vagrant/` (Vagrant private keys for every sandbox VM),
  `infra-{pki,iam,ood}/.env copy`, and
  `infra-rstudio/config/oauth2-proxy.cfg` (live `client_secret` and
  `cookie_secret`). All are now gitignored.
- `scripts/common/purge_git_history.sh`: removes those files and the
  `.env` files committed in early history from every commit, on a mirror
  clone, and lists the secret names to rotate. It never pushes.

### Removed

- Dead copies and backups: `infra-iam/docker-compose.yml_{no,original,problem}`,
  `infra-iam/old/`, `scripts/infra-iam/*_orig`,
  `sandbox/Vagrantfile_{logs_old,nfs,nono,orig}`,
  `infra-rstudio/templates/*_{failed,original_working,original}`,
  `scripts/legacy/`, `scripts/infra-rstudio/{legacy,old_backup}/`, and the
  duplicate `scripts/infra-rstudio/telemetry/telemetry_api.py` and
  `infra-rstudio/lib/biome-portal.js` (identical to the copies the
  Dockerfiles use). All remain in git history.

### Added

- `LICENSE` (Apache-2.0), `.editorconfig`, this changelog.
- `.gitignore`: every `.env` variant except `.env.example` and
  `.env.sandbox`, `.vagrant/`, lab artifacts, `__pycache__/`, local agent
  state (`.serena/`, `.omo/`).

### Upgrade from an untagged checkout

1. If you deploy `infra-rstudio`, keep your existing
   `infra-rstudio/config/oauth2-proxy.cfg`: git no longer tracks it, so
   a pull won't touch it. On a fresh clone, create it from
   `oauth2-proxy.cfg.example`.
2. After the maintainer force-pushes the purged history, delete every old
   clone and clone again.
3. Rotate the secrets listed by `purge_git_history.sh`.
