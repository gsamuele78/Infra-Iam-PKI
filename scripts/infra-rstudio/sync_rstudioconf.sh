#!/bin/bash
set -euo pipefail

# scripts/infra-rstudio/sync_rstudioconf.sh
# ══════════════════════════════════════════════════════════════
# Keeps the RStudio trees of this repo byte-identical to R-studioConf.
#
# R-studioConf is the source of truth for the RStudio stack. Its
# docker-deploy/ and kubernetes-deploy/ are vendored here (mapping and
# pinned commit in infra-rstudio/UPSTREAM.lock). Files listed as "local"
# in a mapping belong to this repo and are never touched; untracked and
# gitignored files (.env, config/site/, oauth2-proxy.cfg, data dirs) are
# never touched either.
#
# Usage:
#   sync_rstudioconf.sh --check  [--source URL|PATH]
#       Verify every vendored file equals the pinned commit (content and
#       exec bit), and that no extra vendored file exists. Exit 1 on drift.
#   sync_rstudioconf.sh --update [--ref REF] [--source URL|PATH]
#       Re-vendor from REF (default: the lock's ref, e.g. main), write the
#       new commit into the lock, and print the upstream log since the old pin.
#
#   --source overrides the lock's repo for this run only (e.g. a local
#   R-studioConf checkout to test an unpushed branch). The lock keeps the
#   canonical URL.
#
# Exit codes: 0 ok | 1 drift / failure | 2 usage error
# ══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOCK="$REPO_ROOT/infra-rstudio/UPSTREAM.lock"

usage() { sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//'; }

for cmd in git jq mktemp cmp; do
    command -v "$cmd" >/dev/null 2>&1 || { echo -e "${RED}Missing required binary: $cmd${NC}" >&2; exit 2; }
done

MODE=""
REF=""
SOURCE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --check)  MODE=check ;;
        --update) MODE=update ;;
        --ref)    REF="${2:?--ref needs a value}"; shift ;;
        --source) SOURCE="${2:?--source needs a value}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo -e "${RED}Unknown argument: $1${NC}" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
[ -n "$MODE" ] || { usage >&2; exit 2; }
[ -f "$LOCK" ] || { echo -e "${RED}Lock file not found: $LOCK${NC}" >&2; exit 2; }
jq -e '.upstream.repo and (.mappings | length > 0)' "$LOCK" >/dev/null \
    || { echo -e "${RED}Malformed lock: $LOCK${NC}" >&2; exit 2; }

REPO_URL="$(jq -r '.upstream.repo' "$LOCK")"
LOCK_REF="$(jq -r '.upstream.ref // "main"' "$LOCK")"
LOCK_COMMIT="$(jq -r '.upstream.commit // ""' "$LOCK")"
SOURCE="${SOURCE:-$REPO_URL}"

WORK="$(mktemp -d /tmp/sync-rstudioconf.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# Blobless bare clone: only the trees/blobs we read are fetched.
git clone --quiet --bare --filter=blob:none "$SOURCE" "$WORK/up.git" 2>/dev/null \
    || git clone --quiet --bare "$SOURCE" "$WORK/up.git"
UP=(git -C "$WORK/up.git")

if [ "$MODE" = check ]; then
    [ -n "$LOCK_COMMIT" ] || { echo -e "${RED}Lock has no pinned commit; run --update first.${NC}" >&2; exit 1; }
    COMMIT="$LOCK_COMMIT"
    "${UP[@]}" cat-file -e "${COMMIT}^{commit}" 2>/dev/null \
        || "${UP[@]}" fetch --quiet origin "$COMMIT" 2>/dev/null \
        || { echo -e "${RED}Pinned commit $COMMIT not found in $SOURCE (not pushed yet?).${NC}" >&2; exit 1; }
else
    want="${REF:-$LOCK_REF}"
    COMMIT="$("${UP[@]}" rev-parse --verify --quiet "${want}^{commit}" \
              || "${UP[@]}" rev-parse --verify --quiet "refs/heads/${want}^{commit}" || true)"
    [ -n "$COMMIT" ] || { echo -e "${RED}Ref '$want' not found in $SOURCE.${NC}" >&2; exit 1; }
fi

# Vendored set of a mapping = files tracked under <to>/ minus its local list.
vendored_files() {
    local to="$1" local_json="$2"
    git -C "$REPO_ROOT" ls-files -z -- "$to" | while IFS= read -r -d '' f; do
        rel="${f#"$to"/}"
        jq -e --arg r "$rel" 'index($r) != null' <<<"$local_json" >/dev/null || printf '%s\n' "$rel"
    done
}

problems=0
nmap="$(jq '.mappings | length' "$LOCK")"
for i in $(seq 0 $((nmap - 1))); do
    from="$(jq -r ".mappings[$i].from" "$LOCK")"
    to="$(jq -r ".mappings[$i].to" "$LOCK")"
    local_json="$(jq -c ".mappings[$i].local // []" "$LOCK")"
    # Optional "files": vendor only these paths (relative to from/) instead of the
    # whole tree; used where the target directory also holds this repo's own scripts.
    files_json="$(jq -c ".mappings[$i].files // null" "$LOCK")"
    dest="$REPO_ROOT/$to"

    # Upstream listing: "<mode> <blob> <path relative to from/>"
    "${UP[@]}" ls-tree -r "$COMMIT" -- "$from/" \
        | awk -v p="$from/" '$2=="blob"{sub("^" p, "", $4); print $1, $3, $4}' > "$WORK/up.list"
    if [ "$files_json" != null ]; then
        awk 'NR==FNR{want[$0]=1; next} ($3 in want)' <(jq -r '.[]' <<<"$files_json") "$WORK/up.list" > "$WORK/up.sel"
        mv "$WORK/up.sel" "$WORK/up.list"
        while read -r rel; do
            awk -v r="$rel" '$3==r{f=1} END{exit !f}' "$WORK/up.list" \
                || { echo -e "${RED}$from/$rel (listed in files) does not exist at $COMMIT${NC}" >&2; problems=$((problems + 1)); }
        done < <(jq -r '.[]' <<<"$files_json")
    fi
    [ -s "$WORK/up.list" ] || { echo -e "${RED}$from/ is empty at $COMMIT${NC}" >&2; exit 1; }

    # A local file must not also exist upstream: ownership would be ambiguous.
    while read -r rel; do
        if awk -v r="$rel" '$3==r{f=1} END{exit !f}' "$WORK/up.list"; then
            echo -e "${RED}$to/$rel is listed as local but also exists upstream in $from/${NC}" >&2
            problems=$((problems + 1))
        fi
    done < <(jq -r '.[]' <<<"$local_json")

    if [ "$files_json" != null ]; then
        # Only the listed files are vendored here; everything else in <to>/ is local.
        jq -r '.[]' <<<"$files_json" | while IFS= read -r rel; do
            git -C "$REPO_ROOT" ls-files --error-unmatch -- "$to/$rel" >/dev/null 2>&1 && printf '%s\n' "$rel"
        done | sort > "$WORK/have.list"
    else
        vendored_files "$to" "$local_json" | sort > "$WORK/have.list"
    fi
    awk '{print $3}' "$WORK/up.list" | sort > "$WORK/want.list"

    if [ "$MODE" = check ]; then
        while read -r mode blob rel; do
            f="$dest/$rel"
            if [ ! -f "$f" ]; then
                echo -e "${RED}MISSING${NC}  $to/$rel"; problems=$((problems + 1)); continue
            fi
            if [ "$(git hash-object "$f")" != "$blob" ]; then
                echo -e "${RED}MODIFIED${NC} $to/$rel (fix it in R-studioConf $from/$rel, then --update)"
                problems=$((problems + 1))
            fi
            if [ "$mode" = 100755 ] && [ ! -x "$f" ]; then
                echo -e "${RED}MODE${NC}     $to/$rel should be executable"; problems=$((problems + 1))
            elif [ "$mode" = 100644 ] && [ -x "$f" ]; then
                echo -e "${RED}MODE${NC}     $to/$rel should not be executable"; problems=$((problems + 1))
            fi
        done < "$WORK/up.list"
        while read -r rel; do
            echo -e "${RED}EXTRA${NC}    $to/$rel (tracked here, absent upstream: delete it, or list it as local)"
            problems=$((problems + 1))
        done < <(comm -23 "$WORK/have.list" "$WORK/want.list")
    else
        while read -r rel; do
            git -C "$REPO_ROOT" rm --quiet -- "$to/$rel"
        done < <(comm -23 "$WORK/have.list" "$WORK/want.list")
        while read -r mode blob rel; do
            mkdir -p "$(dirname "$dest/$rel")"
            "${UP[@]}" cat-file blob "$blob" > "$dest/$rel"
            if [ "$mode" = 100755 ]; then chmod 755 "$dest/$rel"; else chmod 644 "$dest/$rel"; fi
            printf '%s\0' "$to/$rel"
        done < "$WORK/up.list" > "$WORK/stage.list"
        # Stage only what was vendored; local files keep whatever state they had.
        git -C "$REPO_ROOT" add --pathspec-from-file="$WORK/stage.list" --pathspec-file-nul
        echo -e "${BLUE}Vendored${NC} $from/ -> $to/ ($(wc -l < "$WORK/up.list") files)"
    fi
done

if [ "$MODE" = check ]; then
    if [ "$problems" -gt 0 ]; then
        echo -e "${RED}RStudio vendor check: $problems problem(s) against R-studioConf@${COMMIT:0:12}${NC}"
        exit 1
    fi
    echo -e "${GREEN}RStudio vendor check: OK (R-studioConf@${COMMIT:0:12})${NC}"
    exit 0
fi

[ "$problems" -eq 0 ] || exit 1
tmp_lock="$WORK/lock.json"
jq --arg c "$COMMIT" --arg r "${REF:-$LOCK_REF}" '.upstream.commit = $c | .upstream.ref = $r' "$LOCK" > "$tmp_lock"
cp "$tmp_lock" "$LOCK"
git -C "$REPO_ROOT" add -- "$LOCK"

echo -e "${GREEN}Pinned R-studioConf@${COMMIT:0:12}${NC} (ref ${REF:-$LOCK_REF})"
if [ -n "$LOCK_COMMIT" ] && [ "$LOCK_COMMIT" != "$COMMIT" ] \
        && "${UP[@]}" cat-file -e "${LOCK_COMMIT}^{commit}" 2>/dev/null; then
    echo "Upstream changes since ${LOCK_COMMIT:0:12}:"
    mapfile -t froms < <(jq -r '.mappings[].from' "$LOCK")
    "${UP[@]}" log --oneline "${LOCK_COMMIT}..${COMMIT}" -- "${froms[@]}" || true
fi
echo -e "${YELLOW}Review with 'git diff --cached', then run the rstudio gates (validate.sh, compose config, lab tier).${NC}"
