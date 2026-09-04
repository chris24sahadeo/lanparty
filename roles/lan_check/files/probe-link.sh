#!/usr/bin/env bash
# Report the physical state of the interface a machine will actually play over.
#
# Prints one line of JSON. Never fails: an unknown value is reported as "?" rather than an
# error, because a spot check that dies on one machine tells you nothing about the other
# nine.
#
# JSON AND NOT key=value PAIRS. A separator has to survive the trip through YAML and Jinja,
# and a tab does not: in the folded scalar that consumes this, '\t' arrives as a literal
# backslash-t and the split silently returns the whole line as one field. from_json has no
# separator to get wrong. Every value here is a bare token from sysfs, so no escaping is
# needed to emit it.
#
# WHY THIS EXISTS SEPARATELY FROM roles/lan_preflight. Preflight answers "is the LAN path
# being used", which is a yes/no about routing. This answers "and is that path any good",
# which is what you need the moment preflight reports a round trip that cannot be right.
# A 213 ms round trip between two machines on one switch is not a routing fault, and no
# amount of route checking finds it -- link speed, duplex and packet loss do.
#
# WHY A SCRIPT AND NOT AN INLINE shell: TASK -- see the same note in
# roles/quake3_common/files/find-game-data.sh. Ansible parses a free-form shell blob
# looking for chdir= and friends, and an apostrophe in a comment breaks that parse.
set -u

IP="${1:-}"

# The interface that HOLDS the address, not the one a route happens to leave by. When the
# server checks itself the route is `dev lo`, which says nothing about the wire the other
# players' packets arrive on.
DEV=""
if [ -n "$IP" ]; then
  DEV="$(ip -4 -o addr show 2>/dev/null \
         | awk -v ip="$IP" '{ split($4, a, "/"); if (a[1] == ip) { print $2; exit } }')"
fi
# Fall back to whichever interface owns the default route, so a machine with a wrong
# lan_ip still reports something rather than a row of question marks.
if [ -z "$DEV" ]; then
  DEV="$(ip route show default 2>/dev/null | awk '/^default/ { print $5; exit }')"
fi
if [ -z "$DEV" ]; then
  printf '{"dev":"?","speed":"?","duplex":"?","media":"?","mtu":"?","carrier":"?","state":"?"}\n'
  exit 0
fi

read_or_unknown() { [ -r "$1" ] && cat "$1" 2>/dev/null || printf '?'; }

SYS="/sys/class/net/$DEV"

# The kernel creates this directory only for 802.11 interfaces. Cheaper than parsing `iw`
# and needs no extra package on the target.
if [ -d "$SYS/wireless" ]; then
  MEDIA=wifi
else
  MEDIA=wired
fi

# `speed` and `duplex` return EINVAL for a wireless or downed interface, so cat fails and
# read_or_unknown prints "?" -- which is the honest answer, not a zero.
SPEED="$(read_or_unknown "$SYS/speed")"
DUPLEX="$(read_or_unknown "$SYS/duplex")"
MTU="$(read_or_unknown "$SYS/mtu")"
CARRIER="$(read_or_unknown "$SYS/carrier")"
STATE="$(read_or_unknown "$SYS/operstate")"

printf '{"dev":"%s","speed":"%s","duplex":"%s","media":"%s","mtu":"%s","carrier":"%s","state":"%s"}\n' \
  "$DEV" "$SPEED" "$DUPLEX" "$MEDIA" "$MTU" "$CARRIER" "$STATE"
