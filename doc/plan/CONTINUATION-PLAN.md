# Continuation plan (handoff for Claude Code / any agent)

Snapshot: **2026-10-02**. Source of truth for the long-form rationale is
[ALIGNMENT-PLAN.md](ALIGNMENT-PLAN.md) (decisions Q1–Q17, findings D1–D23,
phase checklists and verification gates). This file says **where things stand,
what must be recovered, and the ordered work that is left**, in a form an agent
can execute top to bottom. Update the checkboxes and the snapshot date in the
same PR that does the work.

## 1. Read this first: working rules

1. Two repos, one workflow. Both are on GitHub under `gsamuele78/`:
   - `Infra-Iam-PKI` (this repo), local clone `~/00_Antigravity_workspace/infra/Infra-Iam-PKI`;
   - `R-studioConf`, local clone `~/00_Antigravity_workspace/R-studioConf`.
2. **RStudio code is changed only in R-studioConf.** `infra-rstudio/`,
   `kubernetes-deploy/rstudio/` and the 14 host tools listed in
   `infra-rstudio/UPSTREAM.lock` are byte-identical copies. After an upstream merge:
   `scripts/infra-rstudio/sync_rstudioconf.sh --update --ref main`, then a PR here.
   `--check` (CI job `vendor-check`) rejects hand edits.
3. **PR flow (Q16):** branch → PR → CI green + the phase's local gate → merge commit →
   delete the branch. Never merge red. A lab tier that can't run is written
   "not run" in the PR body.
4. `gh pr edit` and other GraphQL calls fail: the token lacks `read:org`. Use the
   REST API (`gh api -X PATCH repos/<owner>/<repo>/pulls/<n> ...`,
   `gh api -X PUT .../pulls/<n>/merge -f merge_method=merge`).
5. R-studioConf `ci.yml` has `concurrency: cancel-in-progress` per ref: a
   `workflow_dispatch` (needed for the nightly-only **T2 monster build** of the
   RStudio images) cancels the branch's push run. The cancelled run shows as
   "fail" in `gh pr checks`; judge by the `pull_request` run + the dispatch run.
   Don't push to the branch while a dispatch runs.
6. **Never delete local branches you didn't create**, and back up gitignored files
   before a `git pull` that crosses a commit untracking them (a pull deletes files
   that were tracked in the old local HEAD).
7. Host rules: the host Docker daemon stays **off** (it breaks the libvirt lab);
   every container test runs in CI or in the lab VMs.
8. Before saying done: `make lint` and `make validate` here; `make audit` and
   `tests/*.sh` in R-studioConf.

## 2. Current state (verified 2026-10-02)

| Item | State |
| --- | --- |
| Infra-Iam-PKI `main` | `23175ab` (PR #8, deps). Before it: #9 (Serena/LSP tooling, by the maintainer), #7 (RStudio sync, TD-13), #6 (purge lessons), #1 (phases 0–3 + R). CI green. |
| Tags / releases | `v3.1.0` (Phase 0 baseline), `v3.4.0` (phases 1–3 + R). Both re-pointed after the history purge. |
| R-studioConf `main` | `75bf372` (PR #17, deps). Before: #16 (RStudio images build again), #15 (self-contained docker-deploy, back-port). CI green, monster build green on #16/#17. |
| Vendor lock | `infra-rstudio/UPSTREAM.lock` → R-studioConf `47441c5`. **Behind `main` by #17** (step CLI 0.31.0, socket-proxy v0.5.0 in the RStudio images): sync pending, see W1. |
| History purge (Q1) | Done and force-pushed 2026-10-01 (heads + tags). gitleaks on the rewritten history: 0. |
| Open PRs, Infra-Iam-PKI | #4, #5 Dependabot postgres 15 → 18 (major, needs migration: W4). |
| Open PRs, R-studioConf | #18 checkout v4 → v7, #19 curl 8.22.0, #20 base images (rocker 4.4.3, nginx 1.31.0, ollama 0.35.0): W2. #12, #13, #14 are the maintainer's own: don't touch. |
| Lab/sandbox | Never run on 3.4.0. Old `sandbox_*` libvirt domains (Ubuntu 22.04, stale code) are shut off. Host: ~10 GB RAM free, 58 GB free on the `/srv` libvirt pool. |
| Known issues | TD-10 (RStudio host network, by design), TD-12 (K8s OOD image never published, K8s experimental), image CVEs (report-only scan), R-studioConf TD-T2-01 (docker tier behind T1's `Rprofile_site.d/` + audit v28). |

## 3. Recovery items (things lost, exposed or left half-done)

- [ ] **Rotate the 15 leaked secrets on the real hosts** (maintainer). Names only:
      PKI `CA_PASSWORD`, `POSTGRES_PASSWORD`, `SSH_HOST_PROVISIONER_PASSWORD`; IAM
      `DB_PASSWORD`, `KC_ADMIN_PASSWORD`; OOD copies of the PKI ones; RStudio oauth2-proxy
      `client_secret`, `cookie_secret`. `CA_PASSWORD` needs `step crypto change-pass` on
      the CA keys. Record in a private runbook, never in the repo.
- [ ] **GitHub Support "remove sensitive data" request** (maintainer): the pre-purge
      commits are still reachable through PR #1 (`refs/pull/1/head`, e.g. `ef77f0e`)
      and by SHA. Rotation is what actually protects; this only removes the copy.
- [ ] **Every other clone of Infra-Iam-PKI** (other machines, the deployed hosts):
      back up gitignored site files, then `git fetch && git reset --hard origin/main`,
      re-fetch tags, `git reflog expire --expire=now --all && git gc --prune=now`.
- [x] Local site files on the dev host (`infra-rstudio/config/` site files) deleted by a
      pull across the untracking commit: restored 2026-10-01 from the pre-purge bundle.
- **Lost, no action possible: the pre-purge backup bundle** (`/tmp/infra-iam-pki-purge.*`
      was cleared with `/tmp`). The only remaining copies of the old history are the
      GitHub PR #1 refs and any un-reset clone. Nothing else depends on it.
- [ ] R-studioConf local clone: 11 branches deleted by mistake on 2026-10-02 and
      **restored at their exact tips**. Two exist only locally and are not on GitHub:
      `claude/t1-remediation-triage` (`854bbb6`) and `pr3-rebased` (`a1487a4`); one more
      tip is only in the reflog: `__pr3_test` (`e177009`). Maintainer decides: push,
      keep or delete.
- [ ] Decision pending (asked, not answered): the 14 T1 host tools vendored into
      `scripts/infra-rstudio/` — `99_audit_r_environment.sh`, `99_health_check.sh`,
      `99_troubleshoot_env.sh` only work from an R-studioConf checkout. Keep vendored,
      or remove here and run them from R-studioConf.
- [ ] ALIGNMENT-PLAN Phase 0 checkboxes are stale (work done in #1/#6, boxes unticked):
      tick them, leaving only the rotation open. Done in the PR that adds this file.

## 4. Work queue (in order)

Each item: what, where, gate. Version bumps follow ALIGNMENT-PLAN (Q2) unless a
release is folded (Q17).

### W1. Sync R-studioConf #17 into Infra-Iam-PKI

- `sync_rstudioconf.sh --update --ref main` (lock → `75bf372` or newer), PR here.
- Gate: `make lint`, `make validate`; CI `security-scan` infra-rstudio build step = success.

### W2. Dependabot PRs in R-studioConf (RStudio images live there)

| PR | Change | Action |
| --- | --- | --- |
| #18 | `actions/checkout` v4 → v7 in `ai-context.yml`, `ci.yml`, `lint.yml` | merge when CI green |
| #19 | `curlimages/curl` 8.11.1 → 8.22.0 (`rstudio-init`) | merge when CI green |
| #20 | rocker/geospatial 4.4.2 → 4.4.3 (R patch release), nginx 1.27.3 → 1.31.0, ollama 0.5.4 → 0.35.0 | **split**: rocker + nginx in one PR, ollama alone (30 minor releases: model/API compatibility with `r-coder.modelfile` and the telemetry/portal callers must be checked). Dispatch the monster build on each; merge only when green. rocker 4.4.3 changes R: note it in T1/T2 `tier_deltas` if T1 stays on another R. |

Then W1 again (one sync PR may carry several upstream merges).

### W3. Lab tier on the current release (was "not run" everywhere)

- Box: `cloud-image/ubuntu-24.04` (libvirt). `bento/ubuntu-24.04` named in Q7 has
  no libvirt build; record the change in ALIGNMENT-PLAN §3.
- Order and memory (≤ 10 GB): `pki-host` 2 GB → `iam-host` 2 GB → `ood-host` →
  `rstudio-host` (needs the image build; give it ≥ 4 GB and ≥ 40 GB disk).
- Checks, minimum: PKI healthy and fingerprint served; Caddy L4 build (2.11.4 +
  caddy-l4 v0.1.2) and allowlist; `docker stop step-ca` exits without SIGKILL (PID 1);
  `get_certificate.sh` + `scripts/infra-pki/renew_certificate.sh` (exit 0 / 10);
  IAM renewer enrolment + `needs-renewal` path (the sandbox override has no renewer:
  run the production `iam-renewer` service against pki-host); OOD SSO flow
  (`ood-test-sso-flow.sh`); RStudio portal + oauth2-proxy `/ping` + socket-proxy on
  `127.0.0.1:2375` only.
- Destroy the stale `sandbox_*` domains first (`vagrant destroy -f` in `sandbox/`).

### W4. PostgreSQL 15 → 18 (Dependabot #4, #5)

- Not a merge: a migration. Write `doc/` procedure + script: `pg_dumpall` from 15 →
  new empty 18 data dir → restore → step-ca / Keycloak start → verify; rollback =
  old data dir kept. Test in the lab (W3) on PKI and IAM. Then one PR replacing #4/#5
  (close them with a pointer). Check first that Keycloak 26 and step-ca 0.30 list PostgreSQL 18 as supported.

### W5. Architecture follow-ups promised in the 4-VM discussion (not yet in ALIGNMENT-PLAN)

- [ ] Leaf certificate lifetime: step-ca defaults to 24 h, so a CA outage > ~8 h expires
      Keycloak's TLS. Set a longer default/max on the provisioner Keycloak uses (7–30 d)
      and alert before expiry (the renewer healthcheck already turns unhealthy at < 10 %).
- [ ] Chrony on all four hosts against one source (Kerberos 5-min skew, cert validity).
- [ ] DNS: every host resolves `DOMAIN_CA` / `DOMAIN_SSO` by name.
- [ ] `infra-pki/.env.example`: `ALLOWED_IPS` lists the three client hosts + the Docker
      bridge CIDR, not `192.168.0.0/16 10.0.0.0/8`.
- [ ] Later: offline root CA, only the intermediate online.

### W6. ALIGNMENT-PLAN Phase 4 → `v3.5.0`

`tests/lint/check-changelog.sh`, `tests/lint/check-drift.py` (one tag per image across
compose/K8s/scripts/docs — would have caught the 0.29.0 leftovers; `.env.example` vs
variables used; scripts documented; links). Jobs in `lint.yml` and `make lint`.

### W7. Phase 5 → `v3.6.0`

`tests/e2e/lib.sh`, `tests/integration/smoke-{pki,iam,build}.sh`, `backup-restore.sh`,
`tests/lab/run.sh` tier driver, `validate-and-test.yml`, `make test` runs the PKI smoke.

### W8. Phase 6 → `v4.0.0`

Layout move (`sandbox/` → `tests/lab/`, `doc/` → `docs/`), Ubuntu 24.04 lab + Samba AD DC
VM tier (Q8), docs set (architecture, port matrix, hardening, deployment, maintenance,
runbook, troubleshooting, testing, ADRs, roadmap, README rewrite). Update every path in
`.ai/`, workflows, `UPSTREAM.lock` consumers and R-studioConf's `consumers` note.

### W9. Phase 7 → `v4.1.0`

`release.yml`, `IMAGE_TAG` = repo version, `upstream-versions.yml`, release section in
the maintenance guide, branch protection on `main` (maintainer, GitHub settings).

### W10. Upstream debt in R-studioConf (its own PRs)

- TD-T2-01: docker tier to T1's `Rprofile_site.d/` + audit v28 (entrypoint renders the
  fragments), container test, monster build.

## 5. Where the facts live

| Fact | File |
| --- | --- |
| Decisions, findings, phase gates | `doc/plan/ALIGNMENT-PLAN.md` |
| Hard rules, TD list (generated into CLAUDE.md, AGENTS.md) | `.ai/project.yml`, `.ai/agents.md`, `.ai/agents-entry.md` |
| Vendored RStudio pin and mapping | `infra-rstudio/UPSTREAM.lock` |
| T2/T3 deviations from T1 | R-studioConf `.ai/project.yml` `tier_deltas` |
| User-visible changes, upgrade steps | `CHANGELOG.md` (both repos) |
