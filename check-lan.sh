#!/usr/bin/env bash
# Spot check the LAN across every machine in inventory/hosts.yml.
#
# Prints one table: interface, media, link speed, duplex, MTU (Maximum Transmission Unit),
# packet loss and round trip, per machine. Changes nothing and needs no sudo.
#
# Use it when a round trip looks wrong. roles/lan_preflight tells you gameplay traffic is
# on the LAN; this tells you whether that LAN is any good, which is a different question
# with different answers -- a link negotiated at 100 Mb half duplex routes perfectly and
# plays terribly.
#
# Usage:
#   ./check-lan.sh                       every machine in the inventory
#   ./check-lan.sh --limit enrique-Z390  just one
#
# All arguments pass through to ansible-playbook.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# Exports ANSIBLE_CONFIG and provides the vault handling. Sourced rather than repeated:
# this script did NOT have that handling, and the moment a real host_vars/<host>.yml
# existed it died with "Attempting to decrypt but no vault secrets found" -- Ansible
# auto-loads host_vars for every run, encrypted or not.
# shellcheck source=lanparty-lib.sh
source "$REPO_DIR/lanparty-lib.sh"

VENV="$REPO_DIR/.venv"
[[ -x "$VENV/bin/ansible-playbook" ]] || {
  printf '\033[1;31mERROR:\033[0m No virtualenv yet. Run ./bootstrap.sh once first.\n' >&2
  exit 1
}

# No secrets/ here: this playbook diagnoses the network and touches no password.
lanparty_vault_args

exec "$VENV/bin/ansible-playbook" check-lan.yml "${VAULT_ARGS[@]}" "$@"
