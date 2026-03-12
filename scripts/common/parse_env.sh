#!/bin/bash
set -euo pipefail
# parse_env.sh — Safe .env parser (SEC-003 fix)
# Usage: source scripts/common/parse_env.sh [envfile]
# Reads KEY=VALUE lines only; ignores comments and blank lines.
# Does NOT execute arbitrary shell code (unlike 'source .env').
_parse_env() {
    local envfile="${1:-.env}"
    [ -f "$envfile" ] || return 0
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        # Only process KEY=VALUE format
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip surrounding quotes
            val="${val%\"}"
            val="${val#\"}"
            val="${val%\'}"
            val="${val#\'}"
            export "$key"="$val"
        fi
    done < "$envfile"
}
_parse_env "$@"
