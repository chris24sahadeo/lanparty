#!/usr/bin/env bash
# Prove two things that cannot be proved by reading the code:
#
#   1. ISOLATION. A full playbook run leaves ~/.ansible byte-identical. That is the claim
#      the header of ansible.cfg makes, and it is the one that matters -- two other
#      Ansible trees on this workstation depend on the collections in there.
#
#   2. IDEMPOTENCY. A second run reports changed=0.
#
# The playbook runs against a throwaway ubuntu:24.04 container, so nothing here touches
# the machine you are sitting at. Requires docker.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
export ANSIBLE_CONFIG="$REPO_DIR/ansible.cfg"

CONTAINER="lanparty-test-$$"
VENV="$REPO_DIR/.venv"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -x "$VENV/bin/ansible-playbook" ]] || die "Run ./bootstrap.sh first."
command -v docker >/dev/null || die "docker is required."

# Fingerprint rather than checksum the contents: what we care about is that no file was
# added, removed, resized or rewritten. Cheap, and it catches a galaxy install writing a
# tarball into ~/.ansible/tmp, which is the specific accident this guards against.
fingerprint() { find "$HOME/.ansible" -printf '%p %s\n' 2>/dev/null | sort | sha256sum; }

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

log "Starting throwaway container"
docker run -d --name "$CONTAINER" ubuntu:24.04 sleep 3600 >/dev/null
docker exec "$CONTAINER" bash -c \
  'apt-get update -qq && apt-get install -y -qq python3 iproute2 iputils-ping >/dev/null'

# A container has no second machine, so it is both server and client to itself -- which is
# exactly the Phase 1 shape and enough to exercise every role.
# --suffix=.yml IS REQUIRED, not tidiness. Ansible's YAML inventory plugin refuses any
# file whose name does not end in .yml/.yaml/.json, so a bare mktemp name falls through to
# the ini plugin, fails to parse, and the run continues against an EMPTY inventory --
# every play "skipping: no hosts matched" and a recap with no changed= line at all.
INV="$(mktemp --suffix=.yml)"
cat > "$INV" <<EOF
all:
  children:
    game_server:
      hosts:
        $CONTAINER:
          ansible_connection: community.docker.docker
    game_clients:
      hosts:
        $CONTAINER:
          ansible_connection: community.docker.docker
EOF
trap 'cleanup; rm -f "$INV"' EXIT

BEFORE="$(fingerprint)"

log "Run 1"
"$VENV/bin/ansible-playbook" -i "$INV" site.yml

log "Run 2 -- must report changed=0"
OUT="$("$VENV/bin/ansible-playbook" -i "$INV" site.yml)"
echo "$OUT" | tail -5
# Check that the host was reached BEFORE checking what it reported. An unparsed inventory
# or an unreachable container produces a recap with no `changed=` line at all, and without
# this guard that reads as "changed != 0" and gets reported as an idempotency failure --
# which sends you looking in exactly the wrong place.
echo "$OUT" | grep -qE "^$CONTAINER +: +ok=[1-9]" \
  || die "The container was never provisioned -- no play matched it, or it was unreachable.
  This is not an idempotency result. Check the inventory and the connection plugin above."
echo "$OUT" | grep -qE "changed=0 " || die "Second run made changes; something is not idempotent."

AFTER="$(fingerprint)"
[[ "$BEFORE" == "$AFTER" ]] || die "~/.ansible changed during the run. Isolation is broken."

log "PASS: ~/.ansible unchanged, second run clean."
