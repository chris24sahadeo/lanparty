#!/usr/bin/env bash
# Fast gate before a run that needs sudo.
#
# `ansible-playbook --syntax-check` does NOT cover the roles: site.yml pulls them in with
# include_role, which is dynamic, so a role's YAML is not parsed until the task executes.
# A malformed role therefore passes syntax-check and then fails halfway through a
# privileged run. Parsing every file here closes that gap.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
export ANSIBLE_CONFIG="$REPO_DIR/ansible.cfg"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

log "Parsing every YAML file"
./.venv/bin/python - <<'PY'
import pathlib, sys, yaml
bad = []
for f in sorted(pathlib.Path('.').rglob('*.yml')):
    if any(p in ('.venv', '.collections', '.ansible-tmp') for p in f.parts):
        continue
    try:
        yaml.safe_load(f.read_text())
    except Exception as e:
        bad.append(f"{f}: {e}")
for b in bad:
    print(f"FAIL {b}")
sys.exit(1 if bad else 0)
PY

log "Checking shell scripts"
if command -v shellcheck >/dev/null; then
  shellcheck bootstrap.sh test/*.sh
else
  for f in bootstrap.sh test/*.sh; do bash -n "$f"; done
  echo "    (shellcheck not installed; ran bash -n only)"
fi

log "Playbook syntax"
./.venv/bin/ansible-playbook site.yml --syntax-check >/dev/null

log "Inventory"
./.venv/bin/ansible-inventory --graph

log "PASS"
