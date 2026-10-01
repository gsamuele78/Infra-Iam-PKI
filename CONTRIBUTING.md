# Contributing

This repo is the infrastructure as code for an internal PKI, SSO, an Open
OnDemand portal and RStudio Server. Every change must be reviewable as a
diff and validated before merge. Nothing is configured by hand on a host
that the repo can't see.

## Before you open a PR

1. Run the checks CI runs:

   ```bash
   make lint       # shellcheck, .ai/validate.sh, generate.sh --check, RStudio vendor check
   make validate   # docker compose config for the four stacks and the sandbox overrides
   make test       # exits 1 until the tests exist (doc/plan/ALIGNMENT-PLAN.md, Phase 5)
   ```

   Then run the sandbox tier for the stack you touched
   ([doc/SANDBOX_TESTING.md](doc/SANDBOX_TESTING.md)). A green `make lint` on a
   certificate or SSO change proves little on its own.

2. Follow the 14 hard rules (resource limits, bind mounts only, pinned images,
   passwords in files, `set -euo pipefail`, ...). They are listed with their
   rationale in [.ai/agents.md](.ai/agents.md) §4 and enforced by
   `.ai/validate.sh` and the pre-commit hook (`make hooks`).
3. Don't edit RStudio files here. `infra-rstudio/`, `kubernetes-deploy/rstudio/`
   and the host tools listed in `infra-rstudio/UPSTREAM.lock` are copies of
   [R-studioConf](https://github.com/gsamuele78/R-studioConf): change them there,
   then `scripts/infra-rstudio/sync_rstudioconf.sh --update`.
4. Scripts have hidden callers. Read the dependency graph in
   [.ai/agents.md](.ai/agents.md) §7 before changing what a script reads or writes.
5. Update `CHANGELOG.md` under `[Unreleased]`. Add an "Upgrade from X" block
   when an operator has to do something on a host.
6. Never commit real secrets, IPs or hostnames. `.env.example` is the pattern;
   real values stay in the gitignored `.env` and `config/site/` on the host.

If you change `.ai/project.yml`, `.ai/agents.md` or `.ai/agents-entry.md`, run
`make agents` and commit the regenerated files (`CLAUDE.md`, `AGENTS.md`, ...).

## Commit style

Small, logical commits: `type(scope): summary` with `feat`, `fix`, `docs`,
`chore`, `ci`, `security`, `test`, `deps`, `refactor`, `release`.

## Reporting a security issue

See [SECURITY.md](SECURITY.md). Don't open a public issue for vulnerabilities.
