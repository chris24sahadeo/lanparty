#!/usr/bin/env bash
# Add a PC to the LAN party, interactively.
#
# The one step of the setup that still asked a human to open a file and get YAML
# indentation right. Everything this asks for is validated before it is written, and the
# inventory is re-parsed afterwards -- a malformed inventory does not announce itself, it
# just makes Ansible skip the machine and the person wonders why their laptop never got
# the game.
#
# Usage:
#   ./add-machine.sh                                  fully interactive
#   ./add-machine.sh --name joe-laptop --ip 192.168.0.51
#   ./add-machine.sh --name joe-laptop --ip 192.168.0.51 --user joe --yes
#
#   --name   label for the machine in the inventory. Any name you like; it does not have
#            to be the machine's real hostname.
#   --ip     its address on the office LAN.
#   --user   SSH login on that machine. Defaults to the inventory's own ansible_user.
#   --yes    do not ask anything that has an answer already. Implies no prompts, so every
#            other value must come from a flag.
#
# WHY A SCRIPT AND NOT A DOCUMENTED EDIT. The inventory is one flat shape this repo owns,
# so inserting into it is a safe, checkable operation -- and every mistake it prevents
# (a typo'd address, a duplicate entry, a machine that is not actually reachable, a tab
# instead of spaces) is one that otherwise surfaces halfway through a provisioning run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$REPO_DIR/inventory/hosts.yml"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }

NAME=""; IP=""; USER_IN=""; ASSUME_YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --ip)   IP="${2:-}";   shift 2 ;;
    --user) USER_IN="${2:-}"; shift 2 ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    # Print the header block and stop at the first line that is not a comment, rather than
    # a hardcoded line number that goes stale the moment the header is edited.
    -h|--help) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' \
                 "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Unknown argument: $1. Try --help." ;;
  esac
done

# --- prompting -------------------------------------------------------------------------
# Reads come from /dev/tty rather than stdin so this still works when the script itself is
# piped or run from an editor's terminal pane. No tty and no flags means there is nothing
# to read from, which is an error worth naming rather than an empty answer worth accepting.
HAVE_TTY=false
[[ -r /dev/tty ]] && HAVE_TTY=true

ask() {  # ask <prompt> [default] -> prints the answer
  local prompt="$1" default="${2:-}" reply=""
  if [[ "$ASSUME_YES" == true || "$HAVE_TTY" == false ]]; then
    [[ -n "$default" ]] || die "Need a value for '$prompt' and cannot prompt. Pass it as a flag."
    printf '%s' "$default"; return
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " reply </dev/tty || true
    printf '%s' "${reply:-$default}"
  else
    read -r -p "$prompt: " reply </dev/tty || true
    printf '%s' "$reply"
  fi
}

# --yes answers the SAFETY questions ("carry on anyway?"), never the ACTION ones. A flag
# whose name means "stop asking me things" must not thereby start a provisioning run across
# the fleet -- those two offers are gated on $ASSUME_YES being false instead.
confirm() {  # confirm <prompt> -- defaults to yes
  local reply=""
  [[ "$ASSUME_YES" == true ]] && return 0
  [[ "$HAVE_TTY" == false ]] && return 1
  read -r -p "$1 [Y/n] " reply </dev/tty || true
  case "${reply:-y}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# --- validation ------------------------------------------------------------------------
valid_ipv4() {
  local ip="$1" o
  [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  for o in ${ip//./ }; do
    ((10#$o >= 0 && 10#$o <= 255)) || return 1
  done
  return 0
}

# 100.64.0.0/10 is the range Tailscale hands out. This repo deliberately does not use an
# overlay any more, and an address from one here means the game would run over it -- the
# exact mistake dropping the tailnet was meant to make impossible. Plain octet arithmetic
# rather than an ipaddr filter, same as roles/lan_preflight.
is_tailnet() {
  local a b; IFS=. read -r a b _ _ <<<"$1"
  [[ "$a" == "100" ]] && ((10#$b >= 64 && 10#$b <= 127))
}

# A YAML mapping key that needs no quoting. Refusing the rest is better than emitting a
# key that parses as something else -- a name with a colon in it silently becomes a nested
# mapping, and the machine quietly does not exist.
valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; }

# --- the inventory must exist and have the shape we insert into --------------------------
[[ -f "$INVENTORY" ]] || die "No $INVENTORY yet.
  This adds a machine to an existing party. Set up the first machine first --
  see 'Step 1' in README.md, which writes this file for you."

grep -qE '^    game_clients:[[:space:]]*$' "$INVENTORY" \
  || die "$INVENTORY has no 'game_clients:' group at the expected indentation.
  It has been reshaped by hand; add the machine manually, or restore it from
  inventory/hosts.example.yml."
grep -qE '^      hosts:[[:space:]]*$' "$INVENTORY" \
  || die "$INVENTORY has a game_clients group with no 'hosts:' line under it."

DEFAULT_USER="$(sed -n 's/^[[:space:]]*ansible_user:[[:space:]]*//p' "$INVENTORY" | head -1)"
: "${DEFAULT_USER:=$USER}"

# --- gather --------------------------------------------------------------------------
log "Adding a machine to $(basename "$REPO_DIR")"

while :; do
  NAME="$(ask 'Name for this machine (any label)' "$NAME")"
  valid_name "$NAME" && break
  warn "Use letters, digits, dot, dash or underscore, starting with a letter or digit."
  NAME=""
  [[ "$HAVE_TTY" == true && "$ASSUME_YES" == false ]] || die "Invalid --name."
done

while :; do
  IP="$(ask "LAN address for $NAME (its 192.168.x.x)" "$IP")"
  if ! valid_ipv4 "$IP"; then
    warn "'$IP' is not an IPv4 address."
  elif is_tailnet "$IP"; then
    warn "$IP is inside 100.64.0.0/10, the range Tailscale hands out. This repo runs on
       the physical LAN only -- use the address 'ip -4 -br addr' shows on that machine's
       ethernet or wifi interface."
  elif [[ "$IP" == 127.* ]]; then
    warn "$IP is loopback. Other machines cannot reach it."
  else
    break
  fi
  IP=""
  [[ "$HAVE_TTY" == true && "$ASSUME_YES" == false ]] || die "Invalid --ip."
done

USER_IN="$(ask "SSH login on $NAME" "${USER_IN:-$DEFAULT_USER}")"

# --- refuse to add something already there ----------------------------------------------
if grep -qE "^[[:space:]]+${NAME}:[[:space:]]*$" "$INVENTORY"; then
  die "'$NAME' is already in $INVENTORY. Edit it there, or pick another name."
fi
if grep -qE "lan_ip:[[:space:]]*${IP}[[:space:]]*$" "$INVENTORY"; then
  die "$IP is already in $INVENTORY under another name. Two entries for one machine means
  Ansible provisions it twice and the second run fights the first."
fi

# --- is it actually there ----------------------------------------------------------------
log "Checking $NAME at $IP"
if ping -c 2 -W 2 -q "$IP" >/dev/null 2>&1; then
  ok "responds to ping"
else
  warn "no ping response. It may still work (some hosts drop ICMP), but check the machine
       is on and plugged into the same switch."
  confirm "Carry on anyway?" || die "Nothing written."
fi

SSH_OK=false
# BatchMode=yes makes ssh fail rather than prompt, so this is a test and not a login.
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
       "${USER_IN}@${IP}" true >/dev/null 2>&1; then
  SSH_OK=true
  ok "ssh key login works"
else
  warn "cannot log in as ${USER_IN}@${IP} with a key. Ansible needs that."
  # Gated on --yes as well: ssh-copy-id prompts for a password on the terminal, and a run
  # told not to ask questions must not stop dead waiting for one.
  if [[ "$ASSUME_YES" == false ]] \
     && confirm "Run ssh-copy-id now? (it will ask for that machine's password)"; then
    ssh-copy-id -o StrictHostKeyChecking=accept-new "${USER_IN}@${IP}" </dev/tty || true
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${USER_IN}@${IP}" true >/dev/null 2>&1; then
      SSH_OK=true; ok "ssh key login works now"
    else
      warn "still cannot log in. Adding the entry anyway; fix the key before provisioning."
    fi
  fi
fi

# --- write --------------------------------------------------------------------------
# ansible_user is written only when it differs from the group default. Restating a value
# that is already inherited makes the file longer and gives a future reader a second place
# to change it.
ENTRY="        ${NAME}:
          lan_ip: ${IP}"
[[ "$USER_IN" != "$DEFAULT_USER" ]] && ENTRY="${ENTRY}
          ansible_user: ${USER_IN}"

BACKUP="${INVENTORY}.bak"
cp "$INVENTORY" "$BACKUP"

# Edited textually rather than by round-tripping the YAML. A YAML load-and-dump would
# silently discard every comment in the file, and the header of this one is the
# documentation for its own format.
#
# The insertion point is AFTER the last host already in game_clients, not straight after
# `hosts:` -- machines then appear in the order they joined the party, which is the order
# someone reading the file expects. Trailing comments in the group are skipped so a new
# entry never lands in the middle of the worked example at the bottom.
#
# substr() rather than an `^ {8,}` interval: Ubuntu's default awk is mawk, and relying on
# regex interval support across awk implementations is not worth it for one indentation
# test.
INSERT_AFTER="$(awk '
  /^    game_clients:[ \t]*$/ { in_clients = 1; next }
  in_clients && /^    [A-Za-z]/ { in_clients = 0 }
  in_clients && /^      hosts:[ \t]*$/ { last = NR; next }
  in_clients && substr($0, 1, 8) == "        " \
             && $0 !~ /^[ \t]*#/ && $0 !~ /^[ \t]*$/ { last = NR }
  END { print last + 0 }
' "$INVENTORY")"

if [[ "$INSERT_AFTER" -lt 1 ]]; then
  mv "$BACKUP" "$INVENTORY"
  die "Could not find where to insert inside game_clients. $INVENTORY is unchanged."
fi

awk -v n="$INSERT_AFTER" -v entry="$ENTRY" \
  'NR == n { print; print entry; next } { print }' "$BACKUP" > "$INVENTORY"

# --- prove it -----------------------------------------------------------------------
# The write above is text manipulation, so it is checked semantically rather than trusted.
# PyYAML lives in the in-tree venv; before the first ./bootstrap.sh there is none, and a
# structural grep is the honest fallback.
verify_failed() { mv "$BACKUP" "$INVENTORY"; die "$1 $INVENTORY has been restored."; }

if [[ -x "$REPO_DIR/.venv/bin/python" ]]; then
  "$REPO_DIR/.venv/bin/python" - "$INVENTORY" "$NAME" "$IP" <<'PY' || verify_failed "The edited inventory did not parse, or the machine is not in game_clients."
import sys, yaml
path, name, ip = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    doc = yaml.safe_load(fh)
hosts = doc["all"]["children"]["game_clients"]["hosts"]
assert name in hosts, "%s missing from game_clients" % name
assert hosts[name]["lan_ip"] == ip, "lan_ip is not %s" % ip
PY
  ok "inventory parses, and $NAME is in game_clients with lan_ip $IP"
else
  grep -qE "^        ${NAME}:[[:space:]]*$" "$INVENTORY" \
    || verify_failed "The entry is not where it should be."
  ok "entry written (run ./bootstrap.sh once to get the venv, then this is checked properly)"
fi

rm -f "$BACKUP"
log "Added:"
printf '\n%s\n\n' "$ENTRY"

# --- offer to actually do it ----------------------------------------------------------
if [[ "$ASSUME_YES" == false ]] && confirm "Run the network check now? (changes nothing, no sudo)"; then
  "$REPO_DIR/bootstrap.sh" --tags preflight
fi

if [[ "$ASSUME_YES" == false && "$SSH_OK" == true ]] \
   && confirm "Provision $NAME now? (asks for a sudo password)"; then
  "$REPO_DIR/bootstrap.sh" --ask-become-pass
  log "Done. Type 'q' on $NAME to play."
else
  cat <<EOF

Next:
    ./bootstrap.sh --tags preflight     check the network, changes nothing
    ./bootstrap.sh --ask-become-pass    provision it
Then type 'q' on $NAME.
EOF
fi
