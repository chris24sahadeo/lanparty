#!/usr/bin/env bash
# Locate Quake III game data on the control node, so nobody has to type a path.
#
# Prints TWO LINES to stdout:
#     line 1   kind -- "zip" or "dir"
#     line 2   path
# Prints NOTHING if it finds nothing, which is the signal the role uses to decide whether
# to fall back to the rclone remote -- do not make this print a placeholder instead.
# Never fails.
#
# TWO LINES AND NOT ONE DELIMITED LINE. This used to emit <kind>\t<path>, and the tab did
# not survive the trip: in the folded scalar (`>-`) that consumes it, '\t' reaches Jinja as
# a literal backslash-t rather than a tab, so .split() returned the whole line as a single
# field and the path came out EMPTY. The failure then surfaced as "No Quake III game data
# found" on a machine with the file sitting in ~/Downloads all along.
#
# JSON would also fix that, and was tried -- but it needs the path escaped, and hand-rolled
# escaping in shell is its own bug ("${s//\\/\\\\}" does not double a backslash, which is easy
# to write and hard to see). Two lines need no escaping at all: Ansible already splits
# stdout into stdout_lines, so there is no separator anywhere to get wrong. A path may
# contain a space, a quote or a backslash and still arrive intact.
#
# WHY THIS IS A SCRIPT AND NOT AN INLINE shell: TASK. Ansible runs split_args() across a
# free-form shell blob looking for chdir=/creates=, and that parse breaks on an unbalanced
# quote -- including an apostrophe inside a comment. A file has no such hazard and
# shellcheck can read it.
#
# Only the control node needs the data: Ansible pushes whatever this finds to every other
# machine, so one copy in the room is enough.
set -u

REPO="${1:-$PWD}"

# EVERY SEARCH PATH BELOW HANGS OFF $HOME, so getting it wrong finds nothing and the run
# aborts claiming the data is missing when it is sitting in ~/Downloads. That happens the
# moment anyone runs the playbook under sudo: sudo resets HOME to /root, and root has no
# Downloads. bootstrap.sh does not need sudo at the top level -- individual tasks become --
# but "it asked for a password, so I ran the whole thing with sudo" is the obvious wrong
# guess and this makes it harmless.
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
  SUDO_USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  [ -n "$SUDO_USER_HOME" ] && [ -d "$SUDO_USER_HOME" ] && HOME="$SUDO_USER_HOME"
fi
# $USER is used by the removable-media globs below and sudo rewrites it too.
[ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ] && USER="$SUDO_USER"
: "${USER:=$(id -un)}"

emit() { printf '%s\n%s\n' "$1" "$2"; exit 0; }

# Shape 1: a zip holding baseq3/*.pk3, which is how the setup guide ships it.
for z in \
  "$REPO/.gamedata/baseq3.zip" \
  "$HOME/Downloads/baseq3.zip" \
  "$HOME/baseq3.zip" \
  "$HOME/Games/baseq3.zip" \
  "$HOME/Downloads/quake3-data.zip"
do
  [ -f "$z" ] && emit zip "$z"
done

# Shape 2: a directory with pak0.pk3 already in it -- an existing install, or a disc.
for d in \
  "$REPO/.gamedata/baseq3" \
  "$HOME/.steam/steam/steamapps/common/Quake 3 Arena/baseq3" \
  "$HOME/.local/share/Steam/steamapps/common/Quake 3 Arena/baseq3" \
  "$HOME/.steam/root/steamapps/common/Quake 3 Arena/baseq3" \
  "$HOME/GOG Games/Quake III Arena/baseq3" \
  "$HOME/Games/quake3/baseq3" \
  "$HOME/.q3a/baseq3" \
  "/usr/share/games/quake3-data/baseq3"
do
  [ -f "$d/pak0.pk3" ] && emit dir "$d"
done

# Steam libraries on other drives, and mounted discs. Globs, so kept last: these are the
# slow paths and the least likely to hit.
for d in \
  /run/media/*/*/steamapps/common/"Quake 3 Arena"/baseq3 \
  /media/"$USER"/*/steamapps/common/"Quake 3 Arena"/baseq3 \
  /mnt/*/steamapps/common/"Quake 3 Arena"/baseq3 \
  /media/"$USER"/*/baseq3 \
  /media/"$USER"/*/Quake3/baseq3 \
  /mnt/*/baseq3
do
  [ -f "$d/pak0.pk3" ] && emit dir "$d"
done

exit 0
