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

# Same reason as bootstrap.sh: this is the highest-precedence config source, so the in-tree
# collections_path and local_tmp apply no matter where this is called from. See the header
# of ansible.cfg for why that matters on this workstation.
export ANSIBLE_CONFIG="$REPO_DIR/ansible.cfg"

VENV="$REPO_DIR/.venv"
[[ -x "$VENV/bin/ansible-playbook" ]] || {
  printf '\033[1;31mERROR:\033[0m No virtualenv yet. Run ./bootstrap.sh once first.\n' >&2
  exit 1
}

exec "$VENV/bin/ansible-playbook" check-lan.yml "$@"
