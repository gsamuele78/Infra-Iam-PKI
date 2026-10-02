# Alignment plan: Infra-IAM-PKI → reference repo standard

Status: Accepted, in progress. **Next steps and recovery items: [CONTINUATION-PLAN.md](CONTINUATION-PLAN.md).**
Date: 2026-10-01
Reference repo: [gsamuele78/Proxmox_biome_log_collector](https://github.com/gsamuele78/Proxmox_biome_log_collector) at `v0.3.1` (`4cd92b4`)
This repo at analysis time: `main` @ `af8f87e`, 130 commits, **no tags**

This plan brings this repo up to the reference repo's standard for
repo hygiene, constraints-as-CI, testing, documentation, and versioning
and tagging. It also fixes the defects the analysis found. Every phase
lands as one PR, passes a written verification gate, updates
`CHANGELOG.md` and ends with a tag. Phases are ordered so that each one
gives the next a tool it needs: you can't enforce drift before you
have a lint job, and you can't tag before you have a changelog.

---

## 1. How the analysis was done

- Cloned the reference repo and read `AGENTS.md`, `CONTRIBUTING.md`,
  `SECURITY.md`, `Makefile`, `CHANGELOG.md`, every workflow,
  `.github/dependabot.yml`, `.gitleaks.toml`, the `tests/lint/` configs,
  `check-changelog.sh`, `check-drift.py`, `tests/README.md`,
  `docs/testing.md`, `tests/lab/README.md`, `tests/lab/run.sh`,
  `tests/e2e/lib.sh`, `tests/integration/smoke-test.sh`, the ADR
  template, `docs/repo-audit.md` and the maintenance-guide outline.
- Here: listed every tracked file, ran `.ai/validate.sh` (with and
  without `--fix-hint`), `shellcheck -S warning` on every script,
  `docker compose config` per stack against `.env.sandbox`, parsed every
  production compose file for limits and healthchecks, and grepped every
  `image:` line and Dockerfile `FROM` line, plus git history for `.env` files.
- Not run: the Vagrant sandbox, `yamllint`, `markdownlint`, `gitleaks`,
  `trivy` (none of the last four are installed on this host).

---

## 2. Gap analysis

### 2.1 Standards the reference has and this repo lacks

| Area | Reference (`v0.3.1`) | This repo now | Gap |
| --- | --- | --- | --- |
| Versioning | SemVer, `CHANGELOG.md` (Keep a Changelog), tags `v0.2.0`…`v0.3.1` | No tags, no changelog. README says `3.1.0`; `.ai/project.yml` and `.ai/agents.md` say `2.0.0` | **missing / contradictory** |
| Release | `release.yml`: a `vX.Y.Z` tag publishes a GitHub Release from the changelog section | none | missing |
| Changelog check | `tests/lint/check-changelog.sh`: `[Unreleased]` first, headings well formed, every tag has a section | none | missing |
| Drift check | `tests/lint/check-drift.py`: `.env.example` vs stack vars, repeated image tags, every script documented, every test phase/workflow in `docs/testing.md`, relative links | `.ai/validate.sh` covers HC rules only; `generate.sh --check` covers agent files | partial |
| Lint | yamllint, hadolint, shellcheck (blocking), markdownlint, configs in `tests/lint/` | shellcheck **advisory only** (`continue-on-error: true`), `bash -n` | partial |
| Security CI | gitleaks (full history), Trivy config + images (fixable CRITICAL/HIGH fail), weekly cron | none | missing |
| Dependency updates | Dependabot (compose, Dockerfiles, Actions) + `upstream-versions.yml` for what Dependabot can't see | none | missing |
| Integration test | `tests/integration/smoke-test.sh` in CI: boots the stack, waits for health, curls routes, refuses to run if `.env` exists | none in CI | missing |
| E2E / lab | `tests/e2e/tN-*.sh` sourcing `lib.sh` (`check`, `wait_for`, `expect_code`, `summary`), driven by `tests/lab/run.sh`, `make lab-up/lab-test TIER=n`, artifacts gitignored | `sandbox/` Vagrantfile + one ad-hoc `ood-test-sso-flow.sh`; manual protocol in `doc/SANDBOX_TESTING.md` | partial (no assertions, no runner, no tiers) |
| Test map | `docs/testing.md`: layers, CI workflows, lab phases, “what to run for a change”, known gaps | none | missing |
| Entry point | `Makefile`: `lint`, `validate`, `test`, `lab-up`, `lab-test`, `lab-destroy` | none | missing |
| Governance | `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`, `.editorconfig` | none of them (`CLAUDE.md` and `.ai/` exist instead) | missing |
| ADRs | `docs/adr/0000-template.md` + 8 ADRs with alternatives | none; decisions are spread through `.ai/agents.md` | missing |
| Ops docs | architecture, deployment guide, hardening (with control mapping), port matrix, troubleshooting, runbook, maintenance guide (“Where each fact lives”), roadmap, repo audit | per-stack `doc/infra-*/{OVERVIEW,CONFIGURATION,DEPLOY,TROUBLESHOOTING}.md` | partial: per-component docs are good, cross-cutting ones are missing |
| README | CI/version/license badges, live image badges, doc index, testing table | static `Version: 3.1.0`, no badges, claims K8s is “the standard production target” | stale / contradictory |
| Agent rules | `AGENTS.md`: rules + “Before you say done” (make lint/validate/test + lab tier) | `.ai/` generator emits CLAUDE.md, `.cursorrules`, `.clinerules`, `.windsurfrules`, copilot file | stronger in some ways; no “done” gate |

### 2.2 Defects found in this repo (with evidence)

| # | Severity | Finding | Evidence |
| --- | --- | --- | --- |
| D1 | **critical** | Real `.env` files were committed and later deleted, so the secrets are still in git history | `git log -- '*.env'`: `cb2c8d9`, `2a744e6`, `2ec4d5d` … deleted in `a94752d`, `9ca170d` |
| D2 | **high** | Vagrant machine private keys are tracked | `sandbox/.vagrant/machines/{pki,iam,ood,rstudio}-host/libvirt/private_key` |
| D3 | high | `infra-{pki,iam,ood}/.env copy` are tracked. The values look like placeholders, but `.gitignore`'s `*.env` doesn't match `.env copy` and `validate.sh` HC-08 passes them | `git ls-files` |
| D4 | high | HC-07 violated in a Dockerfile: `FROM caddy:builder` and `FROM caddy:latest`. `validate.sh` only scans `image:` lines, so HC-07 still reports “✓” | `infra-pki/caddy/Dockerfile` |
| D5 | high | The CI constraint job is red: `validate.sh` reports 17 HC-03 violations | `.ai/validate.sh --ci --fix-hint` → exit 1 |
| D6 | high | `validate.sh` aborts at the first failure without `--fix-hint`: `hint()` returns 1 under `set -e`, so local and pre-commit runs report one error, not all of them | `.ai/validate.sh:54` |
| D7 | high | `infra-rstudio` compose doesn't render with its own `.env.sandbox` (`HOST_HOME_DIR`, `HOST_PROJECT_ROOT` missing → `invalid spec: :/home`), so the CI `validate-compose` job fails | `docker compose --env-file .env.sandbox config` |
| D8 | medium | 27 scripts lack `set -euo pipefail` (HC-03/rule 3), mostly `infra-rstudio/scripts/*` (container entrypoints included), `scripts/infra-rstudio/{99_*,tools/*}`, `sandbox/sandbox_launcher.sh`, k8s scripts | header scan |
| D9 | medium | 19 files have shellcheck warnings | `shellcheck -S warning` |
| D10 | medium | Long-running services have no healthcheck: `ood-portal`, `infra-rstudio` `oauth2-proxy`, both `docker-socket-proxy`, both `watchtower`, `iam-renewer` | compose parse |
| D11 | medium | Kubernetes drift: `step-cli:0.25.2` (×3 manifests + 2 docs), `osc/ondemand:3.1.0` (doesn't exist), `bitnami/kubectl:1.28`, `ubuntu:22.04` | `grep image: kubernetes-deploy` |
| D12 | medium | Architecture contradiction: README says K8s is “the standard production target” and Compose is “Legacy / Edge”; `.ai/agents.md` says Compose is production and K8s is a future path | README §4, agents.md §1.1 |
| D13 | low | `Dockerfile.keycloak` defaults to `ARG KC_VERSION=25.0.0`. Compose overrides it with `26.0.7`, but a plain `docker build` gets 25 | `infra-iam/Dockerfile.keycloak:3` |
| D14 | low | Dead files tracked: `docker-compose.yml_{no,original,problem}`, `infra-iam/old/`, `deploy_iam.sh_orig`, `reset_iam.sh_orig`, `Vagrantfile_{logs_old,nfs,nono,orig}`, `nginx_site.conf.template_{failed,original_working}`, `portal_index.html.template_original`, `scripts/infra-rstudio/{legacy,old_backup}/`, `legacy_sysadmin_stress_test copy.R`, `scripts/legacy/` | `git ls-files` |
| D15 | low | Duplicated sources: `infra-rstudio/scripts/*` vs `scripts/infra-rstudio/*` (`telemetry_api.py`, `ttyd_login_wrapper.sh`, `test_rstudio_login.sh`), `assets/biome-portal.js` vs `lib/biome-portal.js` | `git ls-files` |
| D16 | low | Commit history isn't scannable (`fix`, `fixes`, `megafix_to_be_checked`) | `git log` |
| D17 | low | Agent-context drift: `CLAUDE.md`'s `<image_versions>` lists `docker-socket-proxy` as `edge`, but compose pins `0.3.0`; `.ai/agents.md` §9 still lists TD-01, TD-02, TD-09, which look fixed | file reads |
| D18 | info | step-ca entrypoint runs `exec step-ca … \| tee`: bash stays PID 1 and signals go to the pipeline, not to step-ca | `infra-pki/docker-compose.yml:114` |

Re-verify before closing (they look fixed, not proven): **TD-01**
(`deploy_pki.sh` now reads `fingerprint/root_ca.fingerprint`), **TD-02**
(`-Xmx1536m`), **TD-03** (no `restart` left in
`scripts/infra-iam/renew_certificate.sh`; find where the restart lives
now), **TD-04** (no `.env:` mount in IAM compose), **TD-09**
(`full_sandbox_launcher.sh` is gone).

### 2.3 What this repo already does better (keep it)

- Hard constraints are written down with IDs and rationale and enforced
  by a script (`.ai/validate.sh`). The reference has a hardening baseline
  but no single validator.
- One source of truth generates context files for many agents
  (`.ai/project.yml` → `generate.sh`), with a `--check` mode in CI.
- Production-parity sandbox: PKI runs the real compose file, OOD builds
  the real Dockerfile.
- Per-component docs for every stack.

The plan **extends** these. It doesn't replace them with the reference's
equivalents.

---

## 3. Decisions (answered 2026-10-01)

| # | Decision | Answer | Consequence for the plan |
| --- | --- | --- | --- |
| Q1 | Purge D1/D2 from history | **Yes, purge and rotate** | Phase 0 ships `tests/lint/purge-history.sh`; the maintainer runs it and force-pushes `origin` and `upstream`, then rotates every secret listed in it |
| Q2 | Version line | `v3.1.0` baseline, minor per phase, `v4.0.0` for the layout move | the layout move lands with the lab (Phase 5), so `v4.0.0` is the lab release |
| Q3 | `doc/` → `docs/`, `sandbox/` → `tests/lab/` | **Move now** | done together with the lab build, not in a later phase |
| Q4 | Production target | **Compose is production, K8s experimental** | ADR-0008; K8s only statically validated (`kubeconform`) |
| Q5 | License | **Apache-2.0** | `LICENSE` + SPDX note in README |
| Q6 | `AGENTS.md` | generated by `.ai/generate.sh` | one source, `generate.sh --check` in CI |
| Q7 | Lab OS | **Ubuntu 24.04** (production hosts run it) | lab box `bento/ubuntu-24.04` on every VM |
| Q8 | Active Directory in the lab | **Yes, top tier** | `dc` VM: Samba AD DC with LDAPS; tests Keycloak LDAP federation and SSSD/Samba join |
| Q9 | Lab resources | the maintainer frees RAM and disk before the full run | the lab is tiered; every tier documents its RAM/disk need; the agent doesn't stop other VMs |
| Q10 | Execution order | phases in order, verified and committed locally, no push | the tag commands are prepared, pushing and tagging stay with the maintainer |
| Q11 | Source of truth for RStudio | **R-studioConf** | `infra-rstudio/`, `kubernetes-deploy/rstudio/` and the T1 host tools in `scripts/infra-rstudio/` are vendored byte-for-byte; this repo owns only the files listed `local` in `infra-rstudio/UPSTREAM.lock` |
| Q12 | Sync mechanism | **vendoring + lock + sync script + CI check** (no submodule) | Phase R |
| Q13 | Changes that were only here | **back-port to R-studioConf first, then sync** | R-studioConf branch `feat/docker-deploy-self-contained` |
| Q14 | Edits to RStudio files here | **frozen until the sync is operative** | no hand edits under the vendored paths; the first release tag waits for Phase R |
| Q15 | Reverse submodule in R-studioConf | **drop it** | R-studioConf `.ai/project.yml` lists this repo under `consumers` |
| Q16 | Push and merge (replaces Q10's "local only") | **one PR per change set, merged by the agent when CI and the local gates are green** | merge commits; lab tiers that can't run are written "not run" in the PR; the history purge (force-push) still needs an explicit go-ahead |
| Q17 | Release of phases 1–3 | **one release, `v3.4.0`** | phases 1, 2, 3 and R only pass CI together (`main` was already red, and the vendored RStudio tree needs the new validator): they land in one PR with one commit per phase; `v3.2.0`/`v3.3.0` are not tagged |

Status of the TD items re-checked on 2026-10-01: TD-01 fixed
(`deploy_pki.sh` reads `fingerprint/root_ca.fingerprint`), TD-02 fixed
(`-Xmx1536m`), TD-04 fixed (no `.env` mount), TD-09 fixed (script
removed). TD-03, TD-05, TD-06 stay open until the lab proves them.

## 4. Rules for the whole plan

- One phase = one branch `align/pN-<slug>` = one PR = one tag after merge.
- Small commits, `type(scope): summary` (`feat`, `fix`, `docs`, `chore`,
  `ci`, `security`, `test`, `deps`, `refactor`, `release`).
- Every PR adds `CHANGELOG.md` lines under `[Unreleased]`, with an
  “Upgrade from X” block whenever an operator must act.
- The gate is the verification table of the phase. Record the output in
  the PR body. A gate that couldn't run is written as **not run**, never
  as passed.
- Fix product bugs in product files. Never work around them in
  `tests/lab/` or `tests/e2e/`.
- No push, tag or release without the maintainer's explicit go-ahead
  (Q1 above is the only force-push).
- The 14 HARD RULES in `CLAUDE.md` apply to every file each phase touches.

Release procedure, used at the end of every phase (written up in
Phase 7, used by hand before then):

```bash
# on main, after the phase PR is merged and CI is green
# 1. move [Unreleased] entries under "## [X.Y.Z] - YYYY-MM-DD", keep an empty [Unreleased]
# 2. bump the version in .ai/project.yml, run .ai/generate.sh
git commit -am "release: X.Y.Z"
tests/lint/check-changelog.sh            # from Phase 4 on
git tag -a vX.Y.Z -m "X.Y.Z"
git push origin main vX.Y.Z               # only when the maintainer says so
```

---

## 5. Phases

### Phase 0: Security hygiene and baseline tag → `v3.1.0`

Goal: no secret or private key reachable in the repo or its history,
dead files gone, a first tag to measure from.

- [x] Inventory every secret ever committed:
      `gitleaks detect --source . --log-opts="--all" --report-path /tmp/gl.json`
      plus `git log --all -p -- '*.env' '*.env copy'`.
- [ ] Rotate every leaked value on the real hosts: `CA_PASSWORD` (step-ca
      key re-encryption with `step crypto change-pass`), `POSTGRES_PASSWORD`,
      `SSH_HOST_PROVISIONER_PASSWORD`, `DB_PASSWORD`, `KC_ADMIN_PASSWORD`,
      OIDC client secrets. Record each one in a private runbook, not here.
- [x] Untrack `sandbox/.vagrant/`, `infra-*/.env copy`, `.serena/`.
      Extend `.gitignore`: `.vagrant/`, `*.env copy`, `.env.*` (keep
      `!.env.example`, `!.env.sandbox`), `sandbox/logs/`,
      `tests/lab/artifacts/`, `__pycache__/`, `.serena/`, `.omo/`.
- [x] Delete the D14 dead files. Check D15 duplicates with `diff`, keep
      the copy compose/Dockerfiles actually use, and delete the other.
- [x] Purge history (Q1):
      `git filter-repo --invert-paths --path-glob '*/.env' --path-glob '*/.env copy' --path sandbox/.vagrant`.
      Force-push both remotes; every clone must re-clone (announce it).
- [x] Add `LICENSE` (Q5) and `.editorconfig` (copy the reference's).
- [x] Create `CHANGELOG.md` with `## [Unreleased]` and
      `## [3.1.0] - <date>`, “Baseline before alignment; see
      doc/plan/ALIGNMENT-PLAN.md”.
- [x] Set `project.version: "3.1.0"` in `.ai/project.yml`, run
      `.ai/generate.sh`, and drop the hard-coded version line from the README.

Verification gate:

| Check | Expected |
| --- | --- |
| `gitleaks detect --source . --log-opts="--all"` | 0 findings (or only allowlisted placeholders) |
| `git ls-files \| grep -E '\.vagrant/\|\.env copy\|_orig$\|_original\|/old/\|old_backup\|/legacy/'` | empty |
| `git ls-files '*.env'` | only `*.env.sandbox` / `*.env.example` |
| `docker compose config --quiet` for pki, iam, ood | exit 0 (same as before) |
| Rotation log | every secret from the inventory marked rotated |

Docs: CHANGELOG, `.gitignore` comments. Tag: **`v3.1.0`**.

---

### Phase 1: Governance files and Makefile → `v3.2.0`

Goal: a contributor (human or agent) finds the rules and the commands in
the places the reference uses.

- [x] `CONTRIBUTING.md`: the reference's structure, plus this repo's
      14 hard rules by reference (link to `.ai/agents.md` §4), commit
      style, and “what to run for a change” (link to `docs/testing.md`,
      filled in by Phase 5).
- [x] `SECURITY.md`: private advisory URL for
      `gsamuele78/Infra-Iam-PKI`, scope (IaC, not upstream images),
      baseline summary, a CA-compromise contact path, supported versions
      (latest tag only).
- [x] `AGENTS.md` generated by `.ai/generate.sh` (Q6): layout table
      with a “Deployed?” column, rules, **“Before you say done”**
      (`make lint`, `make validate`, `make test`, then the lab tier), and
      gotchas (L4 Caddy needs the bridge CIDR in `ALLOWED_IPS`;
      `generate_token.sh` → `configure_iam_pki.sh` coupling; `-T` with
      `docker compose exec`; the `infra-rstudio` host-network exception).
- [x] `Makefile` with targets that are honest from day one:
      `lint` (shellcheck + `validate.sh` until Phase 2 adds the rest),
      `validate` (compose config for all four stacks + sandbox files),
      `test` (prints “no tests yet, see Phase 5” and exits 1, so nothing
      pretends to pass), `agents` (`.ai/generate.sh`), `hooks`
      (`.ai/install-hooks.sh`).
- [x] Fix `.ai/agents.md` §9: mark verified-fixed TDs as fixed with the
      commit that fixed them, keep the rest open. Fix the
      `docker-socket-proxy` version in the generator source (D17).

Verification gate:

| Check | Expected |
| --- | --- |
| `.ai/generate.sh --check` | exit 0 |
| `make validate` | exit 0 for pki, iam, ood (rstudio is fixed in Phase 3; listed as a known failure in the PR) |
| Every relative link in the new files | resolves (checked by hand now, by `check-drift.py` from Phase 4) |

Tag: **`v3.2.0`**.

---

### Phase 2: Lint toolchain and CI that blocks → `v3.3.0`

Goal: the reference's lint and security layers, blocking, on every PR.
The first job of this phase is to make the validator tell the truth.

Fix the validator first:

- [x] D6: `hint() { [[ "$SHOW_HINTS" == true ]] && echo …; return 0; }`.
- [x] HC-07 also scans every `FROM` in every Dockerfile (pinned tag or
      `@sha256`; `caddy:builder` counts as unpinned). Skip build-stage
      aliases.
- [x] HC-08 fails on any tracked file matching `(^|/)\.env($| |\.)` that
      isn't `.env.example` or `.env.sandbox`, and on any tracked
      `private_key`, `*.key` or `*.pem`.
- [x] New check HC-04b: every long-running service has a `healthcheck`
      (one-shot init containers are exempt: `restart: "no"` plus being a
      `service_completed_successfully` dependency).
- [x] Scope: production and sandbox dirs only, after Phase 0 deleted
      `legacy/`.

Lint configs in `tests/lint/` (start from the reference's):

- [x] `.yamllint.yml` (ignore `.git/`, `.serena/`, `.vagrant/`,
      `kubernetes-deploy/**/secrets.yaml` templates if needed).
- [x] `.hadolint.yaml` (trusted registries: docker.io, quay.io, ghcr.io;
      every `ignored:` entry carries a justification comment).
- [x] `.markdownlint.yaml` (MD013 off, MD024 siblings_only, MD033 off,
      MD060 off).
- [x] `.gitleaks.toml` at the root: default rules plus an allowlist for
      `.env.example`, `.env.sandbox`, `docs/**`, and pinned image lines.

Workflows (pin every action to a major version; Dependabot keeps them current):

- [x] `lint.yml`: yamllint, hadolint (matrix over all 13 Dockerfiles),
      shellcheck **blocking** (`-x`, every `*.sh` incl. `infra-*/scripts`
      and `tests/`), markdownlint, `validate.sh --ci --fix-hint`,
      `generate.sh --check`. The changelog and drift jobs come in Phase 4.
- [x] `security-scan.yml`: gitleaks (`fetch-depth: 0`), `trivy config`,
      `trivy image` on the locally built images (`infra-pki-caddy`,
      `infra-iam` init/renewer/keycloak, `infra-ood`, the rstudio images).
      Fixable CRITICAL/HIGH fail; unfixed ones are listed. Weekly cron.
- [x] `.github/dependabot.yml`: `docker-compose` (one entry per stack
      dir + `sandbox/`), `docker` (every Dockerfile dir), `github-actions`.
      Ignore the locally built `infra-*`/`botanical-*`/`rstudio-*` images.
- [x] Remove `ai-context.yml`. Its jobs move into `lint.yml` (constraints,
      agent files) and `validate-and-test.yml` (compose, Phase 5).
- [x] Make the `Makefile` `lint` target run exactly the CI lint jobs.

Then make it green:

- [x] Fix every shellcheck warning (D9) in the product scripts. A
      `# shellcheck disable=` only with a reason on the same line.
- [x] Fix every hadolint, yamllint and markdownlint finding, or justify
      it in the config.

Verification gate:

| Check | Expected |
| --- | --- |
| `make lint` locally | exit 0 |
| Seed test: a branch adding `FROM foo:latest`, a tracked `x/.env copy`, a script without `set -euo pipefail` | `validate.sh` reports **all three** (proves D4/D6 and HC-08 are fixed); branch discarded |
| CI on the PR | `lint`, `security-scan` green |
| `security-scan` trivy report | attached to the PR; unfixed HIGHs listed in `CHANGELOG` “Known issues” |

Tag: **`v3.3.0`**.

---

### Phase 3: Constraint compliance fixes in the product → `v3.4.0`

Goal: everything the new CI catches, fixed in the deployed files.
Behaviour changes are kept minimal, and each one is called out in the
changelog.

- [x] D4: pin `infra-pki/caddy/Dockerfile` (`caddy:2.9.1-builder-alpine`
      → `caddy:2.9.1-alpine`, same version as IAM) and pin the
      `caddy-l4` module to a commit or version in `xcaddy build --with`.
- [x] D8: `set -euo pipefail` in all 27 scripts. For each one, read the
      script and fix what strict mode breaks (unset `$1`, `grep` with no
      match in a pipeline, `(( x++ ))` at 0). Container entrypoints
      (`infra-rstudio/scripts/entrypoint_*.sh`, `infra-ood/scripts/docker-entrypoint.sh`)
      are tested by booting the container in the Phase 5 smoke test.
- [x] Rules 13/14: `command -v` assertions and `trap … EXIT` cleanup in
      every script that uses external binaries or temp files (the
      `script-safety-review` skill checklist).
- [x] D10: healthchecks for `ood-portal` (Apache `/` or
      `/nginx/stage`), `oauth2-proxy` (`/ping`), `docker-socket-proxy`
      (`wget -qO- http://localhost:2375/_ping`), `watchtower`
      (`--health-check`), `iam-renewer` (cert file exists and is valid
      for more than N hours: `step certificate needs-renewal` inverted).
- [x] D7: add `HOST_HOME_DIR` and `HOST_PROJECT_ROOT` to
      `infra-rstudio/.env.sandbox` and `.env.example`. Make compose fail
      loudly when they're unset (`${HOST_HOME_DIR:?set HOST_HOME_DIR}`).
- [x] Add `.env.example` where it's missing (`infra-ood/`). Every
      stack gets `.env.example` (production placeholders) and
      `.env.sandbox` (test values).
- [x] D13: `ARG KC_VERSION=26.0.7` in `Dockerfile.keycloak`.
- [x] D18: step-ca entrypoint without `| tee`. Send step-ca output to
      stdout (the json-file driver already keeps it), or use
      `exec > >(tee -a …)` before `exec step-ca` so step-ca is PID 1.
- [x] D11 + Q4: bring the K8s manifests to the compose versions
      (`step-cli:0.29.0`; replace `osc/ondemand:3.1.0` with the image
      built from `Dockerfile.ood`; current `kubectl` tag). Add a banner
      “experimental, not the production target” to
      `kubernetes-deploy/doc/OVERVIEW.md`, and fix the README §4 claim.
- [x] TD-03, TD-05, TD-06: re-verify. Fix TD-03 if it still restarts
      Keycloak every loop (restart only when `step ca renew` actually
      renewed). TD-05 is documented as accepted. TD-06 stays pinned to
      `ondemand=4.1.*`; record the exact version in a build arg.

Verification gate:

| Check | Expected |
| --- | --- |
| `make lint` + `.ai/validate.sh --ci` | exit 0, zero HC violations |
| `make validate` | all four stacks + all sandbox files render with `.env.sandbox` |
| `docker compose build` per stack | exit 0 |
| `docker compose up -d` PKI on a clean dir, then `docker compose ps` | every long-running service `healthy`, one-shots `exited (0)` |
| `kubeconform -strict -summary kubernetes-deploy/` | 0 invalid |
| Sandbox: `vagrant destroy -f && vagrant up` (all four VMs) | every VM provisions; record the `sandbox/logs/summary.log` table in the PR |

Changelog: one “Changed” line per behaviour change; an “Upgrade from
3.3.0” block (rebuild the caddy image; new required rstudio vars).
Tag: **`v3.4.0`**.

---

### Phase 4: Drift and changelog checks → `v3.5.0`

Goal: docs and code can't disagree without CI going red.

- [ ] `tests/lint/check-changelog.sh`: copy the reference's (it's
      repo-agnostic).
- [ ] `tests/lint/check-drift.py` (stdlib only), rules adapted to this repo:
  1. **env**: per stack, every `${VAR}` in `docker-compose.yml` is in
     both `.env.example` and `.env.sandbox`, every declared var is read
     by compose or by a script in `scripts/infra-<stack>/`, and every
     line is a comment or `KEY=value` (with an allowlist for dormant vars).
  2. **tags**: each upstream image (`smallstep/step-ca`, `step-cli`,
     `postgres`, `caddy`, `watchtower`, `docker-socket-proxy`,
     `oauth2-proxy`, `keycloak`) has **one** tag across all production
     compose files, sandbox files, Dockerfiles, `kubernetes-deploy/`,
     the Makefile, workflows and `.ai/project.yml`.
  3. **docs**: every file under `scripts/` and every `infra-*/scripts/*.sh`
     is named in some Markdown file; every `tests/e2e/t*.sh` and every
     workflow is in `docs/testing.md`.
  4. **links**: every relative Markdown link resolves.
  5. **constraints ↔ docs**: every `HC-NN` in `.ai/project.yml` appears
     in `docs/hardening.md` (Phase 6) and in `validate.sh`.
  6. **version**: `.ai/project.yml` `project.version` equals the newest
     `CHANGELOG.md` release heading.
- [ ] Add the `changelog` and `drift` jobs to `lint.yml` and to `make lint`.
- [ ] Fix every problem the first run finds, on the side that's wrong.

Verification gate:

| Check | Expected |
| --- | --- |
| `python3 tests/lint/check-drift.py` | `drift check: 0 problem(s)` |
| `tests/lint/check-changelog.sh` | `CHANGELOG.md: OK (N releases)` and every `v*` tag covered |
| Seed test: bump `step-cli` in one k8s manifest only; add a var to one compose file only | drift reports both; branch discarded |

Tag: **`v3.5.0`**.

---

### Phase 5: Integration and end-to-end tests → `v3.6.0`

Goal: CI proves every stack boots and the trust chain works. The lab
proves the multi-host flows. Every assertion prints `PASS`/`FAIL`, and
every phase exits non-zero on failure.

Shared harness:

- [ ] `tests/e2e/lib.sh`: port the reference's `pass`, `fail`, `check`,
      `check_not`, `wait_for`, `expect_code`, `summary`, plus
      PKI-specific helpers: `ca_health` (`step ca health`),
      `cert_issued_by_root <crt>` (`step certificate verify --roots`),
      `fingerprint_matches`, `port_not_published <svc> <port>`,
      `all_healthy <compose-file>`.

CI layer (`.github/workflows/validate-and-test.yml`, runs on the GitHub runner):

- [ ] `compose-config`: every stack + sandbox file with `.env.sandbox`.
- [ ] `tests/integration/smoke-pki.sh`: refuses to run if `infra-pki/.env`
      exists; copies `.env.sandbox`, runs **`scripts/infra-pki/deploy_pki.sh`**
      (the documented path, not a bare `compose up`), then asserts:
      all services healthy, `configurator` and `fingerprint-writer`
      exited 0; `GET :80/fingerprint/root_ca.fingerprint` equals
      `step certificate fingerprint root_ca.crt`; `step ca health` over
      :9000 with `--fingerprint`; ACME, SSH-POP and ssh-host-jwk
      provisioners present; Postgres not published on the host;
      bind-mount ownership `PUID:PGID`; `verify_pki.sh` exit 0.
      Tears down with a `trap`.
- [ ] `tests/integration/smoke-iam.sh` (needs PKI up on the same
      runner): `generate_token.sh` → `configure_iam_pki.sh` (Workflow B
      in agents.md), `deploy_iam.sh` non-interactive, Keycloak healthy,
      Keycloak's cert chains to the root, Caddy serves `DOMAIN_SSO` with
      a cert from the CA (`--resolve`), `-Xmx` ≤ container limit.
- [ ] `tests/integration/smoke-build.sh`: build the OOD and rstudio
      images and run each container's entrypoint to healthy with
      `.env.sandbox` (no AD; SSSD/Samba sidecars only start).
- [ ] `tests/integration/backup-restore.sh`: `backup_pki.sh` →
      `reset_pki.sh` (with `yes` piped in) → restore → the same root
      fingerprint and the same issued-cert serials.

Lab layer (the four-VM Vagrant topology, `make lab-up TIER=n && make lab-test TIER=n`):

| Tier | Phase file | VM | Proves |
| --- | --- | --- | --- |
| 0 | `t0-pki.sh` | pki-host | `smoke-pki.sh` on a real daemon; Caddy L4 allowlist rejects a source outside `ALLOWED_IPS` |
| 1 | `t1-iam.sh` | iam-host | trust bootstrap from the fingerprint endpoint, Keycloak healthy, renewer enrolls and renews, Keycloak restarted only when the cert changed (TD-03) |
| 1 | `t1-enroll-ssh.sh` | iam-host (as a client) | `join_pki.sh ssh-host`: host cert installed, sshd uses it, systemd timer present, a forced renewal through SSH-POP |
| 1 | `t1-client-trust.sh` | ood-host | `setup_client_trust.sh` refuses a wrong fingerprint, installs with the right one |
| 1 | `t1-after-reboot.sh` | all | stacks come back healthy after `vagrant reload` |
| 2 | `t2-ood-oidc.sh` | ood-host | `ood-test-sso-flow.sh` (moved here) logs in through Keycloak and lands on the dashboard |
| 2 | `t2-rstudio.sh` | rstudio-host | oauth2-proxy redirects unauthenticated users, accepts the OOD session, RStudio is reachable; host-network services listen only on the expected ports |
| 3 | `t3-ca-reinit.sh` | pki + iam | PKI re-init → new fingerprint → Workflow B → IAM trusts the new root (the documented recovery) |

- [ ] `tests/lab/run.sh` host driver (port the reference's, with the
      rsync-by-name guard), artifacts in `tests/lab/artifacts/`
      (gitignored). Until Phase 6 moves the lab, it lives at
      `sandbox/run.sh` and Makefile targets point there.
- [ ] Lab-only values (`192.168.56.*`, sandbox passwords) never in
      production files. Drift rule: no `192.168.56.` outside
      `sandbox/`/`tests/`, `.env.sandbox` and docs.
- [ ] `make test` runs `smoke-pki.sh` (no longer exits 1).
- [ ] `docs/testing.md` (draft at `doc/testing.md` until Phase 6):
      layers table, CI workflows table, lab phases table, “what to run
      for a change” (e.g. `infra-pki/` or `scripts/infra-pki/` → CI
      green + lab tier 1; `join_pki.sh` → tier 1; Keycloak theme →
      lint + tier 2; image bump → CI green + tier 1; a release → highest
      touched tier from `vagrant destroy -f`), known gaps (no real AD,
      no real HPC scheduler, K8s only statically validated).

Verification gate:

| Check | Expected |
| --- | --- |
| CI `validate-and-test` | all jobs green, `timeout-minutes` set on every job |
| Seed test: break `fingerprint-writer`'s output path on a branch | `smoke-pki.sh` FAILs on the fingerprint assertion (proves the test can fail); branch discarded |
| `make lab-up TIER=3 && make lab-test TIER=3` from clean | every phase `OK`; summary pasted into the PR |
| `check-drift.py` | every `t*.sh` and workflow listed in testing.md |

Tag: **`v3.6.0`**.

---

### Phase 6: Documentation restructure and layout → `v4.0.0`

Goal: the reference's documentation set, with every fact in one place.
This is the breaking phase (paths move).

Layout moves (Q3), done with `git mv` so history follows:

- [ ] `doc/` → `docs/`; per-stack folders become `docs/components/<stack>/`.
- [ ] `sandbox/` → `tests/lab/` (Vagrantfile `rsync` target and
      `/workspace/...` paths, Makefile, scripts, docs). Lab compose
      overrides keep their names.
- [ ] `doc/plan/ALIGNMENT-PLAN.md` → `docs/plan/ALIGNMENT-PLAN.md`, with
      phases checked off as they land, as the reference's
      `EXECUTION-PLAN.md` is.

New or rewritten docs:

- [ ] `docs/architecture.md`: the 4-host topology (Mermaid), trust
      chain, boot sequences, network isolation and the rstudio
      host-network exception (moved out of `.ai/agents.md` §2 and §6;
      agents.md links to it).
- [ ] `docs/network-port-matrix.md`: every published port per host,
      source allowed, what enforces it (Caddy L4 allowlist, host firewall).
- [ ] `docs/hardening.md`: one row per HC rule (ID, rule, rationale, what
      enforces it: `validate.sh` check / CI job / review only); the
      container baseline; TLS/PKI policy (JWK bootstrap, SSH-POP renewal,
      no `--insecure`). The drift check (Phase 4, rule 5) keeps it
      complete.
- [ ] `docs/deployment-guide.md`: Workflow C from scratch, per host, the
      operator scripts only, with the verification command after each step.
- [ ] `docs/maintenance-guide.md`: rules, **“Where each fact lives”**
      (e.g. image tag → compose file; repeats checked by drift), bump an
      image, add an env var, add a service, add an HC rule, release,
      upgrade a deployment.
- [ ] `docs/runbook-incident-response.md`: CA down, cert expiry,
      suspected CA key compromise (revoke, re-init, Workflow B on every
      dependent), Keycloak down, AD LDAPS cert rotation, restore from backup.
- [ ] `docs/troubleshooting.md`: merge the per-stack TROUBLESHOOTING
      files plus the sandbox-discovered bug table (agents.md §8.4).
- [ ] `docs/testing.md` (final), `tests/README.md` (copy-paste commands),
      `tests/lab/README.md` (requirements, topology, tiers, lab-only creds).
- [ ] `docs/adr/0000-template.md` + backfilled ADRs (status Accepted,
      dated to when the decision was made where git shows it): 0001
      step-ca with PostgreSQL; 0002 Caddy L4 in front of step-ca; 0003
      bind mounts only; 0004 docker-socket-proxy for the renewer; 0005
      JWK bootstrap + SSH-POP renewal; 0006 OOD built from apt.osc.edu
      debs; 0007 `network_mode: host` for infra-rstudio; 0008 Compose is
      production, K8s experimental (Q4); 0009 generated agent context
      (`.ai/`); 0010 repo layout and versioning (this plan).
- [ ] `docs/repo-audit.md`: §2 of this plan as a findings table with
      “Fixed by” filled in.
- [ ] `docs/roadmap.md`: deferred work (K8s migration, real AD in the
      lab, HPC scheduler integration) and why.
- [ ] `README.md` rewrite on the reference's pattern: CI badges for
      `lint`, `validate-and-test` and `security-scan`, a semver tag badge,
      a license badge, dynamic image badges read from the compose files,
      a short why/what, the Mermaid diagram, quick start, doc index,
      testing table, contributing and license.
- [ ] `.ai/generate.sh` and the generated files point at the new paths;
      CLAUDE.md §3 directory tree regenerated.

Verification gate:

| Check | Expected |
| --- | --- |
| `make lint` (markdownlint + drift links/docs rules) | exit 0 |
| `grep -rn 'doc/infra-\|sandbox/' --include='*.md' --include='*.sh' --include='Vagrantfile' --include='Makefile' .` | only historical mentions in CHANGELOG/ADR/plan |
| `make lab-up TIER=1 && make lab-test TIER=1` from clean at the new path | all `OK` |
| A cold read: someone who didn't write it follows `deployment-guide.md` in the lab | PKI + IAM up with no step outside the guide; findings fixed |

Changelog: “Upgrade from 3.6.0”: old → new path table, re-clone note
for the lab, and no change on deployed hosts beyond the doc paths.
Tag: **`v4.0.0`**.

---

### Phase R: RStudio vendored from R-studioConf (before the first tag)

Goal: a change made in R-studioConf reaches this repo through one tested
PR, and a hand edit of a vendored file here is a CI error.

State found (2026-10-01): of 83 non-asset `infra-rstudio/` files, 32 were
identical to R-studioConf, the rest had drifted both ways; `kubernetes-deploy/rstudio`
had an invalid manifest (`telemetry-api-deployment.yaml` lost its `containers:`
key); 6 tracked config files held real e-mail addresses and AD settings that
R-studioConf had already de-tracked; `setup_nodes.vars.conf` still held 4 real
SMTP/contact values.

- [x] Untrack the 6 site files, gitignore them, add them (and a value
      redaction for `setup_nodes.vars.conf`) to `purge_git_history.sh`.
- [x] R-studioConf branch `feat/docker-deploy-self-contained` (commit
      `37fdb32`, **not pushed**): per-file 3-way back-port of this repo's
      changes (base = newest blob both histories share), docker-deploy
      self-contained, socket-proxy off the host network, telemetry COPY fix,
      `.env.sandbox.example` resolves, K8s pins + NetworkPolicies, validator
      bugs fixed, contract test `tests/docker_deploy_self_contained.sh`,
      reverse submodule dropped, `tier_deltas` TD-T2-01..04.
- [x] `infra-rstudio/UPSTREAM.lock` (3 mappings: docker-deploy, kubernetes-deploy,
      14 T1 host tools by file list) and `scripts/infra-rstudio/sync_rstudioconf.sh`
      (`--check` / `--update`, never touches local or gitignored files).
- [x] `.ai/validate.sh`: script checks skip vendored files (upstream gate +
      `--check` cover them); HC-03 now requires the first code line to be the
      `set` line (a commented `#set -e` no longer passes).
- [x] Workflows `rstudio-vendor-check.yml` (every push/PR on the vendored
      paths) and `rstudio-upstream-sync.yml` (weekly PR).
- [x] R-studioConf PR #15 merged (`6523d05`); it also greened CI that was red on its `main` (bats, nginx render test, hadolint 2.14, certbot-nginx).
- [x] Re-pinned: lock `ref: main`, commit `6523d05`.
- [ ] Lab tier `rstudio-host` with the vendored tree (both auth backends).
- [ ] R-studioConf follow-up TD-T2-01: port T1 `Rprofile_site.d/` + audit
      v28 to the docker tier; it arrives here through the weekly sync PR.

Verification gate:

| Check | Expected |
| --- | --- |
| `sync_rstudioconf.sh --check` | `RStudio vendor check: OK` |
| `--update` twice in a row | second run stages nothing |
| hand edit / chmod / stray file under a vendored path | `--check` exits 1 naming `MODIFIED` / `MODE` / `EXTRA` |
| `docker compose config` before vs after the first sync | only the intended deltas (socket-proxy, healthchecks, oauth2-proxy tag, admin-recipients mount) |
| R-studioConf `make audit` + `tests/docker_deploy_self_contained.sh` | PASS (and the test fails on a broken COPY or a missing template) |

---

### Phase 7: Release automation and upkeep → `v4.1.0`

Goal: tagging publishes a release, the version can't drift, and
updates arrive by themselves.

- [ ] `.github/workflows/release.yml`: copy the reference's (tag push or
      manual with a tag; notes extracted from `## [X.Y.Z]`; fails if the
      section is missing; `gh release create --verify-tag`). Backfill
      releases `v3.1.0` … `v4.0.0` with `workflow_dispatch`.
- [ ] Locally built images take the repo version: `IMAGE_TAG` defaults
      to the version from `.ai/project.yml`, and the drift rule checks it
      (no more `v1.0.0` forever on the botanical images).
- [ ] `upstream-versions.yml` (weekly): compares what Dependabot can't
      see (the OOD deb version in `Dockerfile.ood`, the `caddy-l4`
      module pin, step-ca vs step-cli kept equal) with upstream, and
      opens one issue per outdated item, never a PR.
- [ ] `docs/maintenance-guide.md` “Release” section = §4's procedure,
      plus “run the highest touched lab tier from clean before tagging”.
- [ ] Branch protection on `main` (maintainer action in GitHub settings):
      required checks `lint`, `validate-and-test`, `security-scan`.

Verification gate:

| Check | Expected |
| --- | --- |
| `git tag v4.1.0 && git push origin v4.1.0` (with the maintainer's go-ahead) | GitHub Release `4.1.0` with exactly the changelog section |
| README version badge | shows `v4.1.0` |
| `gh release list` | every tag from `v3.1.0` has a release |
| Dependabot | first grouped PRs open and go through the same CI |

Tag: **`v4.1.0`**.

---

## 6. Effort and order

| Phase | Tag | Rough effort | Needs the lab |
| --- | --- | --- | --- |
| 0 Security hygiene | v3.1.0 | 0.5 day + secret rotation on hosts | no |
| 1 Governance | v3.2.0 | 0.5 day | no |
| 2 Lint + CI | v3.3.0 | 1–2 days (shellcheck fixes dominate) | no |
| 3 Product fixes | v3.4.0 | 2–3 days | yes (full sandbox) |
| 4 Drift checks | v3.5.0 | 1 day | no |
| 5 Tests | v3.6.0 | 3–5 days | yes (tiers 0–3) |
| 6 Docs + layout | v4.0.0 | 2–3 days | yes (tier 1) |
| 7 Release automation | v4.1.0 | 0.5 day | no |

Phases 0 → 2 must run in order. Phase 4 can run in parallel with
Phase 3 once Phase 2 is merged. Phase 6's doc writing can start during
Phase 5, but the moves land after Phase 5 is tagged.

## 7. Definition of done for the whole plan

- `make lint validate test` green locally; `lint`, `validate-and-test`
  and `security-scan` required and green on `main`.
- `.ai/validate.sh --ci` reports 0 violations, and the seed tests in
  Phases 2, 4 and 5 showed each check can fail.
- `make lab-test TIER=3` green from a clean `vagrant destroy -f`.
- Every tag from `v3.1.0` to `v4.1.0` has a changelog section and a
  GitHub Release.
- `docs/repo-audit.md` lists D1–D18 with the commit that fixed each one.
- gitleaks over full history: 0 findings.
