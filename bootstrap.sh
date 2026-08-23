#!/usr/bin/env bash
# Bring up the LAN party control node, then run the playbook.
#
# Everything this script creates lives inside the repo. It installs no global tool, adds
# no apt source, and writes nothing under ~/.ansible -- see the header of ansible.cfg for
# why that matters on this particular workstation.
#
# Usage:
#   ./bootstrap.sh                      full run against inventory/hosts.yml
#   ./bootstrap.sh --tags preflight     LAN path check only, changes nothing
#   ./bootstrap.sh --check --diff       dry run
#   ./bootstrap.sh --limit chris-framework
#
# All arguments pass through to ansible-playbook.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# Matched to what the other Ansible trees on this workstation pin. Not because we share
# their interpreter -- we deliberately do not -- but because trees agreeing on one core
# version means a bug reproduces the same way in all three.
ANSIBLE_CORE_VERSION="2.21.2"
VENV="$REPO_DIR/.venv"

# The single most important line in this repo. ANSIBLE_CONFIG is the highest-precedence
# config source, so exporting it here means our collections_path and local_tmp apply no
# matter what the caller's CWD or environment looks like.
export ANSIBLE_CONFIG="$REPO_DIR/ansible.cfg"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- ansible-core, in-tree -------------------------------------------------------------
# Stock `python3 -m venv`, NOT `uv tool install`. ~/.local/bin/ansible-playbook is a uv
# shim shared with the two other Ansible trees on this machine; installing over it at a
# different version would hijack theirs.
if [[ ! -x "$VENV/bin/ansible-playbook" ]]; then
  log "Creating in-tree virtualenv at .venv"
  python3 -m venv "$VENV" 2>/dev/null || die \
    "python3 -m venv failed. Install the venv module first: sudo apt install python3-venv"
  "$VENV/bin/pip" install --quiet --upgrade pip
fi

INSTALLED_CORE="$("$VENV/bin/python" -c \
  'import ansible.release; print(ansible.release.__version__)' 2>/dev/null || echo none)"
if [[ "$INSTALLED_CORE" != "$ANSIBLE_CORE_VERSION" ]]; then
  log "Installing ansible-core==$ANSIBLE_CORE_VERSION (found: $INSTALLED_CORE)"
  "$VENV/bin/pip" install --quiet "ansible-core==$ANSIBLE_CORE_VERSION"
fi

# --- collections, in-tree ---------------------------------------------------------------
# -p .collections is redundant with collections_path in ansible.cfg, and stated anyway:
# a bare `ansible-galaxy collection install` here would upgrade the copies that layers 1
# and 2 depend on, and that failure is silent. Two mechanisms, deliberately.
if [[ ! -d "$REPO_DIR/.collections/ansible_collections/community/general" ]]; then
  log "Installing pinned collections into .collections/"
  "$VENV/bin/ansible-galaxy" collection install \
    -r "$REPO_DIR/requirements.yml" -p "$REPO_DIR/.collections"
fi

# --- become ------------------------------------------------------------------------------
# Play-level become is false; individual tasks opt in. Ask for the sudo password only when
# sudo actually needs one, so a --tags preflight run (which touches nothing privileged)
# never prompts.
BECOME_ARGS=()
if ! sudo -n true 2>/dev/null; then
  # --ask-become-pass reads the password with getpass, which needs a real terminal to turn
  # echo off. Without one it silently returns an empty string and the run dies fourteen
  # tasks later with "sudo: a password is required", which does not look like a terminal
  # problem at all. Fail here instead, where the message can say what to do.
  if [[ ! -t 0 ]]; then
    die "Tasks here need sudo, and there is no terminal to read the password from.
  Any of these work:
      # from an interactive shell
      ./bootstrap.sh $*
      # or warm the sudo timestamp first, then rerun anywhere
      sudo -v && ./bootstrap.sh $*
      # or authenticate through a desktop dialog, no terminal needed
      SUDO_ASKPASS=/path/to/askpass sudo -A -v && ./bootstrap.sh $*
  A --tags preflight run needs no sudo and works anywhere."
  fi
  log "Some tasks need sudo; you will be prompted once."
  BECOME_ARGS+=(--ask-become-pass)
fi

log "Running site.yml"
exec "$VENV/bin/ansible-playbook" site.yml "${BECOME_ARGS[@]}" "$@"
