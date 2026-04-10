---
name: script-safety-review
description: Reviews shell scripts for safety and compliance with Infra-IAM-PKI project standards. Use when creating, modifying, or reviewing any .sh file in the scripts/ directory. Checks error handling, secret safety, interactive input rules, and script coupling.
---

# Script Safety Review Skill

You are reviewing a shell script for the Infra-IAM-PKI project.

## Mandatory Checks

### 1. Error Handling & Robustness (HC-03, HC-13, HC-14)
- Second line MUST be `set -euo pipefail`
- Shebang MUST be `#!/bin/bash`
- **Dependency Assertion (HC-13)**: Must explicitly verify required external binaries via `command -v <pkg> >/dev/null 2>&1 || exit 1`.
- **Deterministic Cleanup (HC-14)**: Must use `trap 'rm -rf /tmp/...' EXIT ERR` when managing temporary files.

### 2. Secret Safety (HC-04)
- Passwords MUST be written to files via `printf "%s" "$VAR" > file`
- NEVER pass passwords as CLI arguments (`--password "$VAR"`)
- NEVER `echo "$PASSWORD"` (leaks in process table)
- Use `--password-file` flags where available

### 3. Interactive Input Rules
Check which category this script belongs to:

**Container-internal (NEVER use read -p):**
- `scripts/infra-pki/init_step_ca.sh`
- `scripts/infra-pki/patch_ca_config.sh`
- `scripts/infra-iam/fetch_pki_root.sh`
- `scripts/infra-iam/fetch_ad_cert.sh`
- `scripts/infra-iam/renew_certificate.sh`
- `infra-rstudio/scripts/entrypoint_rstudio.sh`
- `infra-rstudio/scripts/entrypoint_nginx.sh`
- `infra-rstudio/scripts/entrypoint_auth_pet.sh`
- `infra-rstudio/scripts/manage_pki_trust.sh`
- `infra-rstudio/scripts/docker-entrypoint.sh`
- `infra-rstudio/scripts/maintenance_entrypoint.sh`

If the script is in this list and contains `read -p`, `read -rp`, or `read -s`, it WILL hang when run inside a Docker container. This is a **critical failure**.

**Operator scripts (interactive allowed):**
All other scripts in `scripts/` that are run by the sysadmin, including:
- `scripts/infra-rstudio/deploy_rstudio.sh`
- `scripts/infra-rstudio/reset_rstudio.sh`
- `scripts/infra-rstudio/validate_rstudio.sh`
- `scripts/infra-rstudio/configure_rstudio_pki.sh`
- `scripts/infra-rstudio/backup_rstudio.sh`

### 4. Config Reading
- CORRECT: `grep "^VAR=" .env | cut -d= -f2- | tr -d '"'`
- WRONG: `source .env` (unsafe with special characters in passwords)

### 5. Path Resolution
- MUST use: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- NEVER use `pwd` or hardcoded absolute paths

### 6. Script Coupling
Before modifying what a script READS or PRODUCES, check the dependency chain:

```
generate_token.sh → {host}_join_pki.env → configure_iam_pki.sh → .env → deploy_iam.sh
```

Read `.ai/agents.md` Section 7.1 for the complete dependency graph.

### 7. Destructive Operations (HC-10)
- Reset/destroy scripts MUST require explicit confirmation (`type 'yes'`)
- Deploy scripts MUST `exit 1` if `chown` fails
- Use colored output: GREEN (success), RED (error), YELLOW (warning), BLUE (info)

### 8. JSON Manipulation (HC-12)
- Use `jq` for ALL JSON operations
- NEVER use `sed`, `awk`, or `grep` to modify JSON files
- URL-encode credentials: `jq -nr --arg v "$VAR" '$v|@uri'`

## Output Format

```
[PASS/FAIL/WARN] Check: description
  Line N: problematic code
  → Fix: specific fix
```
