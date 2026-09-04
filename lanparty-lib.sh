#!/usr/bin/env bash
# Shared setup for the entry-point scripts. Sourced, never executed.
#
# WHY THIS FILE EXISTS. The vault handling below started life inline in bootstrap.sh, and
# check-lan.sh -- written before the vault did -- did not have it. The moment a real
# host_vars/<host>.yml appeared, every playbook that was not bootstrap.sh died with
# "Attempting to decrypt but no vault secrets found", because Ansible auto-loads host_vars
# for ANY run and cannot read an encrypted one without the key. One copy, sourced, so a
# fourth entry point cannot reintroduce that.

# ANSIBLE_CONFIG is the highest-precedence config source, so exporting it here means this
# repo's collections_path and local_tmp apply no matter what the caller's CWD or
# environment looks like. See the header of ansible.cfg for why that matters on this
# workstation.
export ANSIBLE_CONFIG="$REPO_DIR/ansible.cfg"

lanparty_log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
lanparty_die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Populates VAULT_ARGS with --vault-password-file when there is a key to use, and fails
# loudly when there are encrypted files and no key -- rather than letting Ansible fail
# later with a message that does not say which file or what to do about it.
lanparty_vault_args() {
  VAULT_ARGS=()
  if [[ -f "$REPO_DIR/vault-password" ]]; then
    VAULT_ARGS+=(--vault-password-file "$REPO_DIR/vault-password")
    return
  fi
  local encrypted=()
  local f
  for f in "$REPO_DIR"/host_vars/*.yml "$REPO_DIR"/secrets/*.yml; do
    [[ -f "$f" ]] || continue
    head -1 "$f" | grep -q '^\$ANSIBLE_VAULT' && encrypted+=("${f#"$REPO_DIR"/}")
  done
  if (( ${#encrypted[@]} )); then
    lanparty_die "These files are encrypted and there is no vault-password file to open them:
      ${encrypted[*]}
  The key is generated once and is not recoverable if lost. Either restore it, or delete
  those files and re-enter what they held:
      ./add-machine.sh --name <host> --sudo-pass     for a machine's sudo password"
  fi
}

# secrets/*.yml override the placeholder passwords in group_vars/all.yml -- rcon today,
# whatever a future game needs after that. -e is the HIGHEST precedence source, so a real
# password beats the shipped "changeme" without editing a tracked file.
#
# -e IS THE RIGHT SCOPE HERE and the wrong one for sudo. An rcon password belongs to the
# SERVER, so one value for the whole run is correct; a sudo password belongs to a machine,
# which is why those live in host_vars/ instead.
lanparty_secret_args() {
  SECRET_ARGS=()
  local f
  for f in "$REPO_DIR"/secrets/*.yml; do
    [[ -f "$f" ]] && SECRET_ARGS+=(-e "@$f")
  done
}
