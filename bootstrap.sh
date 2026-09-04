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

# A preflight-only run is every task in roles/lan_preflight, and every one of them is a
# probe with become: false. It genuinely needs no sudo, so do not ask for a password and
# do not die on a missing terminal -- which is what the message below promises. Matched on
# the arguments rather than inferred, because this is the only tag selection that is
# entirely become-free.
PREFLIGHT_ONLY=false
# Initialised because `set -u` is on, and assigned at the END of each iteration so the
# `preflight` case sees the argument BEFORE it.
PREV_ARG=""
for arg in "$@"; do
  case "$arg" in
    --tags=preflight|-t=preflight)
      PREFLIGHT_ONLY=true
      ;;
    preflight)
      if [[ "$PREV_ARG" == "--tags" || "$PREV_ARG" == "-t" ]]; then
        PREFLIGHT_ONLY=true
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

# THE PROBE MUST RUN THE WAY ANSIBLE WILL RUN SUDO, NOT THE WAY THIS SHELL WOULD.
#
# Ansible's sudo become plugin builds `sudo -H -S -n ...` and spawns it from a Python
# subprocess with no controlling terminal. sudo's default timestamp_type is `tty`, so a
# ticket is keyed to the terminal it was obtained on -- which means a plain `sudo -n true`
# HERE can succeed off this terminal's ticket while Ansible's sudo, having no terminal,
# still needs a password. The run then dies at the first `become: true` task with
# "sudo: a password is required", long after this check said everything was fine.
#
# Warming the timestamp first (`sudo -v && ./bootstrap.sh`) makes that MORE likely, not
# less, which is the opposite of what anyone expects.
#
# setsid detaches the probe from the controlling terminal, so it is asking the same
# question Ansible will ask. Falls back to the naive probe if setsid is missing.
sudo_works_without_a_terminal() {
  if command -v setsid >/dev/null 2>&1; then
    setsid sudo -n true </dev/null >/dev/null 2>&1
  else
    sudo -n true </dev/null >/dev/null 2>&1
  fi
}

if [[ "$PREFLIGHT_ONLY" == false ]] && ! sudo_works_without_a_terminal; then
  # --ask-become-pass reads the password with getpass, which needs a real terminal to turn
  # echo off. Without one it silently returns an empty string and the run dies fourteen
  # tasks later with "sudo: a password is required", which does not look like a terminal
  # problem at all. Fail here instead, where the message can say what to do.
  if [[ ! -t 0 ]]; then
    die "Tasks here need sudo, and there is no terminal to read the password from.
  Any of these work:
      # from an interactive shell
      ./bootstrap.sh $*
      # or give this user passwordless sudo for the run
      #   sudo visudo   ->   $USER ALL=(ALL) NOPASSWD: ALL
      # or hand the password to Ansible itself, vaulted -- the only route that does not
      # depend on a sudo timestamp, which is scoped to a terminal this has none of
      #   ./bootstrap.sh $* -e @secrets/become.yml --vault-password-file vault-password
  A --tags preflight run needs no sudo and works anywhere."
  fi
  log "Some tasks need sudo; you will be prompted once."
  BECOME_ARGS+=(--ask-become-pass)
fi

log "Running site.yml"
exec "$VENV/bin/ansible-playbook" site.yml "${BECOME_ARGS[@]}" "$@"
