#!/usr/bin/env bash
# Locate Quake III game data on the control node, so nobody has to type a path.
#
# Prints one line to stdout:   <kind>\t<path>      kind is "zip" or "dir"
# Prints nothing if it finds nothing. Never fails.
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

emit() { printf '%s\t%s\n' "$1" "$2"; exit 0; }

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
