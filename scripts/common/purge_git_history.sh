#!/bin/bash
set -euo pipefail
# scripts/common/purge_git_history.sh
# ══════════════════════════════════════════════════════════════
# One-shot history purge (ALIGNMENT-PLAN Phase 0, decision Q1).
#
# Removes from EVERY commit the files that once held secrets or
# machine keys, working on a fresh mirror clone so the operator's
# checkout is never touched. It never pushes: it prints the push
# commands and the list of secret NAMES (never values) to rotate.
#
# Usage:
#   scripts/common/purge_git_history.sh [SOURCE_REPO_URL_OR_PATH]
#   (default source: the repo this script lives in)
#
# Requires: git, git-filter-repo (apt install git-filter-repo | pipx install git-filter-repo)
# ══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

for cmd in git git-filter-repo mktemp grep sort; do
    command -v "$cmd" >/dev/null 2>&1 || { echo -e "${RED}Missing required binary: $cmd${NC}" >&2; exit 1; }
done

# Paths purged from history. Keep in sync with .gitignore and
# docs/repo-audit.md (findings D1, D2, D3, D20).
PURGE_PATHS=(
    "infra-pki/.env"
    "infra-iam/.env"
    "infra-ood/.env"
    "infra-rstudio/.env"
    "infra-pki/.env copy"
    "infra-iam/.env copy"
    "infra-ood/.env copy"
    "infra-rstudio/config/oauth2-proxy.cfg"
    # Site PII (real e-mail addresses, AD topology)
    "infra-rstudio/config/admin_recipients.txt"
    "infra-rstudio/config/user_email_map.txt"
    "infra-rstudio/config/scopri_progetti_known.conf"
    "infra-rstudio/config/lib_kerberos_setup.vars.conf"
    "infra-rstudio/config/join_domain_sssd.vars.conf"
    "infra-rstudio/config/join_domain_samba.vars.conf"
)
PURGE_GLOBS=(
    "sandbox/.vagrant/*"
    "tests/lab/.vagrant/*"
)
# Files that stay tracked (sanitized today) but whose OLD revisions held site
# values. Their values are redacted in every revision with --replace-text;
# the replacement list is built at run time in the work dir and never printed.
# Format: "<path>|<KEY1> <KEY2> ..."
# Only values that are private: --replace-text rewrites them in EVERY file of
# every revision, HEAD included. MAIL_DOMAIN is the public institutional domain
# and appears in the live Keycloak theme, so it is not redacted.
REDACT_KEYS=(
    "infra-rstudio/config/setup_nodes.vars.conf|BIOME_CONTACT SENDER_EMAIL SMTP_DNS_SERVERS SMTP_HOST"
)

WORK="$(mktemp -d /tmp/infra-iam-pki-purge.XXXXXX)"
trap 'echo -e "${BLUE}Work dir kept for inspection: $WORK${NC}"' EXIT

echo -e "${BLUE}[1/5] Mirror clone of $SOURCE into $WORK/repo.git${NC}"
git clone --quiet --mirror "$SOURCE" "$WORK/repo.git"
cd "$WORK/repo.git"

echo -e "${BLUE}[2/5] Backup bundle (restore with: git clone $WORK/before-purge.bundle)${NC}"
git bundle create "$WORK/before-purge.bundle" --all >/dev/null

echo -e "${BLUE}[3/5] Secret variable NAMES found in the purged files (values are not printed)${NC}"
: > "$WORK/rotate.txt"
for p in "${PURGE_PATHS[@]}"; do
    while read -r rev; do
        [ -n "$rev" ] || continue
        git show "$rev:$p" 2>/dev/null \
            | grep -E -i '^\s*[A-Za-z_]*(PASS|SECRET|TOKEN|KEY)[A-Za-z_]*\s*=' \
            | sed -E 's/\s*=.*//; s/^\s+//' \
            | sed "s#^#$p: #" >> "$WORK/rotate.txt" || true
    done < <(git log --all --format=%H -- "$p")
done
sort -u -o "$WORK/rotate.txt" "$WORK/rotate.txt"
cat "$WORK/rotate.txt"

# Build literal replacements for REDACT_KEYS from every historical revision.
: > "$WORK/replacements.txt"
chmod 600 "$WORK/replacements.txt"
for entry in "${REDACT_KEYS[@]}"; do
    p="${entry%%|*}"
    for key in ${entry#*|}; do
        while read -r rev; do
            [ -n "$rev" ] || continue
            git show "$rev:$p" 2>/dev/null \
                | grep -E "^${key}=" | cut -d= -f2- | tr -d '"' \
                | grep -vE '^$|__FILL_ME__|example' \
                | sed 's/$/==>__REDACTED__/' >> "$WORK/replacements.txt" || true
        done < <(git log --all --format=%H -- "$p")
    done
done
sort -u -o "$WORK/replacements.txt" "$WORK/replacements.txt"
echo "Values to redact in kept files: $(wc -l < "$WORK/replacements.txt") (list not printed)"

echo ""
echo -e "${YELLOW}This rewrites every commit SHA. Every clone must be re-cloned afterwards.${NC}"
read -r -p "Type 'yes' to rewrite the mirror in $WORK/repo.git: " answer
[ "$answer" = "yes" ] || { echo -e "${RED}Aborted. Nothing rewritten.${NC}"; exit 1; }

echo -e "${BLUE}[4/5] git filter-repo${NC}"
args=(--force --invert-paths)
for p in "${PURGE_PATHS[@]}"; do args+=(--path "$p"); done
for g in "${PURGE_GLOBS[@]}"; do args+=(--path-glob "$g"); done
[ -s "$WORK/replacements.txt" ] && args+=(--replace-text "$WORK/replacements.txt")
git filter-repo "${args[@]}"

echo -e "${BLUE}[5/5] Verify: no purged path left in any commit${NC}"
left="$(git log --all --format= --name-only | sort -u | grep -E '(^|/)\.env( copy)?$|\.vagrant/|oauth2-proxy\.cfg$|infra-rstudio/config/(admin_recipients\.txt|user_email_map\.txt|scopri_progetti_known\.conf|lib_kerberos_setup\.vars\.conf|join_domain_(sssd|samba)\.vars\.conf)$' || true)"
if [ -n "$left" ]; then
    echo -e "${RED}Still present after filter-repo:${NC}"; echo "$left"; exit 1
fi
if [ -s "$WORK/replacements.txt" ]; then
    leaked=0
    mapfile -t all_revs < <(git rev-list --all)
    while IFS= read -r line; do
        v="${line%==>__REDACTED__}"
        if git grep -qF -e "$v" "${all_revs[@]}" -- 2>/dev/null; then leaked=1; break; fi
    done < "$WORK/replacements.txt"
    [ "$leaked" -eq 0 ] || { echo -e "${RED}A redacted value is still present in history.${NC}"; exit 1; }
fi
echo -e "${GREEN}History clean.${NC}"

cat <<EOF

Next steps (manual, by the maintainer):
  1. Rotate every secret listed above on the real hosts
     (list saved in $WORK/rotate.txt; record the rotation privately).
  2. Check that HEAD did not change, then push branches and tags (not
     --mirror: GitHub rejects the read-only refs/pull/* and the push errors):
       cd $WORK/repo.git
       git rev-parse 'main^{tree}'   # must equal the tree of origin/main before the purge
       git push --force <remote-url> 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
  3. Every working copy: fetch, `git reset --hard origin/main`, re-fetch the tags,
     then `git reflog expire --expire=now --all && git gc --prune=now`; delete old
     clones. Gitignored files survive a reset, but files that were tracked in your
     old local HEAD and untracked upstream are deleted by a pull: back them up first.
  4. Old commits stay reachable through every pull request's refs/pull/N/head
     and by SHA. Only GitHub Support can drop them ("remove sensitive data"
     request listing the PRs); rotation (step 1) is what actually protects you.
EOF
