#!/bin/bash
# pull-logs.sh
# Pulls provisioning logs from all running sandbox VMs to sandbox/logs/ on the host.
#
# Usage:
#   sandbox/pull-logs.sh                  # one-shot pull from all live VMs
#   watch -n10 sandbox/pull-logs.sh       # auto-pull every 10s (follow long builds)
#   sandbox/pull-logs.sh pki-host         # pull from a single VM only
#
# Output:
#   sandbox/logs/pki-host/start-pki.log
#   sandbox/logs/iam-host/start-iam.log
#   sandbox/logs/ood-host/start-ood.log
#   sandbox/logs/summary.log

set -euo pipefail
cd "$(dirname "$0")"   # always run from sandbox/

# Map: hostname → private IP → key path
declare -A VM_IPS=(
  [pki-host]="192.168.56.10"
  [iam-host]="192.168.56.20"
  [ood-host]="192.168.56.30"
)
declare -A VM_KEYS=(
  [pki-host]=".vagrant/machines/pki-host/libvirt/private_key"
  [iam-host]=".vagrant/machines/iam-host/libvirt/private_key"
  [ood-host]=".vagrant/machines/ood-host/libvirt/private_key"
)

# Optional: filter to a single VM if passed as argument
TARGET="${1:-}"

pull_vm() {
  local vm="$1"
  local ip="${VM_IPS[$vm]}"
  local key="${VM_KEYS[$vm]}"

  # Skip if key doesn't exist (VM never started)
  if [ ! -f "$key" ]; then
    return 0
  fi

  # Quick connectivity check (1s timeout, no output)
  if ! ssh -i "$key" \
       -o StrictHostKeyChecking=no \
       -o LogLevel=ERROR \
       -o ConnectTimeout=1 \
       -o BatchMode=yes \
       "vagrant@${ip}" "true" 2>/dev/null; then
    echo "  [skip] ${vm} (${ip}) — not reachable"
    return 0
  fi

  mkdir -p "logs/${vm}"
  rsync -az \
    -e "ssh -i ${key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=3" \
    "vagrant@${ip}:/workspace/Infra-Iam-PKI/sandbox/logs/" \
    "logs/" \
    2>/dev/null && echo "  [ok]   ${vm} → logs/${vm}/" || echo "  [err]  ${vm} — rsync failed"
}

echo "[$(date '+%H:%M:%S')] Pulling logs from sandbox VMs..."

if [ -n "$TARGET" ]; then
  pull_vm "$TARGET"
else
  for vm in pki-host iam-host ood-host; do
    pull_vm "$vm"
  done
fi

echo "[$(date '+%H:%M:%S')] Done. Logs are in sandbox/logs/"
