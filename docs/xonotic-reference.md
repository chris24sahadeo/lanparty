# Xonotic on Ubuntu: the facts worth not rediscovering

Everything here was checked against Xonotic 0.8.6 on Ubuntu 24.04 -- `cvarlist` from the
shipped binaries, `ss -lunp` against a running server, the configs inside the game's own
`.pk3` files. Where a number below contradicts something you remember, this is the one that
was measured.

The sibling document `quake3-reference.md` covers the other game. The two engines look
alike and agree on almost nothing.

## Packages

**There is no `xonotic` package in Ubuntu 24.04** -- not in main, universe or multiverse.
`darkplaces` in universe is the bare Quake engine that Xonotic's engine was forked from; it
has none of Xonotic's game code, and cannot play it.

So the engine comes from upstream's release archive. What apt is still for is the shared
libraries that archive expects to find:

| package | what breaks without it |
| --- | --- |
| `libsdl2-2.0-0` | nothing starts. The only hard link-time dependency |
| `libpng16-16t64` | PNG textures, loading screen |
| `libfreetype6` | all text, including the menu |
| `libvorbisfile3` | all sound and music |
| `libtheora0` | intro and map cinematics |
| `libcurl4t64` | HTTP map downloads from a server |
| `unzip` | unpacking the archive on the target |

All but SDL2 are **dlopen'd at runtime**, so a missing one is not a startup error -- it is
a silently degraded game. `libsdl2-2.0-0` pulls in the X11, Wayland, ALSA (Advanced Linux
Sound Architecture) and PulseAudio libraries.

`libjpeg` is deliberately **not** in that list. 0.8.6's binaries contain no reference to it
at all; the JPEG decoder is built in.

## The release archive

`https://dl.xonotic.org/xonotic-0.8.6.zip`, 1,238,439,495 bytes. Upstream publishes
`xonotic-0.8.6.sha512` beside it, which is why this repo pins a SHA-512 and not a SHA-256 --
that is the digest that actually exists to check against. `dl.illwieckz.net` and
`dl.unvanquished.net` serve the identical file.

Unlike Quake III, **the data is freely licensed** -- GPL-2 engine, GPL / CC-BY-SA
(Creative Commons Attribution-ShareAlike) art, maps, sounds and music. There is no search
script, no rclone remote and no USB stick: `get_url` with a checksum is the whole story.
It is still gitignored, for size rather than law.

Roughly 105 MB of the archive is for other operating systems:

| | size |
| --- | --- |
| `Xonotic.app/` -- macOS bundle with an embedded SDL2 framework | 27 MB |
| `*.exe` -- Windows engines, 32- and 64-bit | 71 MB |
| `bin32/`, `bin64/` -- the Windows DLLs those need | 10 MB |
| `xonotic-osx-dedicated` | 3 MB |
| `misc/` -- mapping tools and an rsync auto-updater | 3 MB |

`source/` (28 MB) is **kept**. It is the corresponding source for the GPL binaries this
repo copies onto other people's machines.

Excluding those saves disk on the target and *no* transfer at all: Ansible pushes the whole
zip and unzips on the far end, so exclusions apply after the copy.

## Paths

| | |
| --- | --- |
| install prefix | `/opt/Xonotic` |
| client engine | `/opt/Xonotic/xonotic-linux64-sdl` |
| dedicated engine | `/opt/Xonotic/xonotic-linux64-dedicated` |
| game data | `/opt/Xonotic/data/*.pk3` -- 7 files, 1.18 GB |
| player's writable dir | `~/.xonotic/data/` |
| server's writable dir | `<userdir>/data/`, i.e. `/var/games/xonotic-server/data/` |

`/opt` and not `/usr/lib`: Quake III lives under `/usr/lib/quake3` because a Debian package
puts it there and two AppArmor profiles are written against that path. Nothing about
Xonotic is packaged, **there is no AppArmor profile for it**, and a self-contained add-on
application tree is what the FHS (Filesystem Hierarchy Standard) reserves `/opt` for.

The capital X is upstream's own directory name inside the archive.

### userdir and gamedir

`-userdir <path>` is a startup option, not a cvar. The engine appends its gamedir, which for
Xonotic is literally `data`, so `-userdir /var/games/xonotic-server` produces
`/var/games/xonotic-server/data/`. **No trailing slash is needed** -- checked, not assumed.

That is the same shape as a player's `~/.xonotic/data`, and it is why a config at
`/etc/anything` is unreachable: `exec` resolves against the engine's virtual filesystem,
whose writable root is `<userdir>/<gamedir>`.

## The config chain

`quake.rc`, from inside the game data, is the whole startup sequence. Reading it is worth
more than any summary:

```
exec default.cfg          the entire shipped ruleset, ~6900 cvars
exec config.cfg           WRITTEN BY THE ENGINE on every clean exit
exec data/campaign.cfg
exec config_update.cfg
exec font-xolonium.cfg
exec autoexec/*.cfg
exec autoexec.cfg         <-- ours
stuffcmds                 <-- `+foo bar` arguments from the command line run HERE
...
exec post-config.cfg      cvar-saving machinery, not a config
```

Two consequences, and they are the same two as Quake III's.

**Never install a config as `config.cfg`.** The engine rewrites it from live cvar state on
every clean exit, so a tuned config under that name survives exactly until the first player
quits.

**`autoexec.cfg` is not a workaround here -- it is the intended slot.** The shipped data
pk3 contains an `autoexec.cfg` whose entire contents are:

```
// placeholder file, is replaced by autoexec.cfg in user home directory
```

A real file at `~/.xonotic/data/autoexec.cfg` shadows it, because loose files in the
gamedir win over pk3 contents.

Verified exec order from a real run: `... autoexec/empty.cfg`, `autoexec.cfg`, then
`effects-high.cfg` -- the first line of ours. A missing `lanparty-local.cfg` prints
`couldn't exec lanparty-local.cfg` and continues.

### The effects presets must come first

`effects-{omg,low,med,normal,high,ultra,ultimate}.cfg` ship inside the game data, and each
is a block of about eighty `r_*` and `cl_*` settings that **overwrites whatever it covers**.
The engine's own default is `effects-normal.cfg`, exec'd from `xonotic-client.cfg`. Run one
after your own graphics settings and it quietly undoes them.

## `rate` is a command, not a cvar

This is the one that costs an afternoon. `cvarlist` says:

```
_cl_rate is "40000" ["40000"] internal storage cvar for current rate (changed by rate command)
```

There is no cvar named `rate`. `seta rate 1000000` silently creates a brand new cvar, saves
it to `config.cfg` forever, and changes nothing. The correct line is bare `rate 1000000`,
and `_cl_rate` is where it lands.

`maxplayers` is the same shape -- a command, no cvar behind that name.

## Verified defaults

Client (`xonotic-linux64-sdl`, `cvarlist`):

| cvar | default | note |
| --- | --- | --- |
| `cl_maxfps` | 250 | |
| `cl_maxidlefps` | 20 | already low; raising it is the wrong direction |
| `cl_netfps` | 60 | "should match or be a multiple of `sys_ticrate`" |
| `cl_netimmediatebuttons` | 1 | already on |
| `cl_netrepeatinput` | 1 | packet-loss insurance; redundant on a switch |
| `_cl_rate` | 40000 | set via the `rate` command |
| `vid_vsync` | 0 | already off |
| `vid_fullscreen` | 1 | |
| `vid_desktopfullscreen` | 1 | **makes `vid_width`/`vid_height` inert** |
| `vid_width` / `vid_height` | 1024 / 768 | |
| `vid_pixelheight` | 1 | |
| `showfps` | 0 | |
| `fov` | 100 | 1-170 allowed |
| `sensitivity` | 3 | |

Server (`xonotic-linux64-dedicated`, `cvarlist`):

| cvar | default | note |
| --- | --- | --- |
| `sv_public` | **1** | on the client build it is 0. See below |
| `sv_maxrate` | 1000000 | the ceiling the client's `rate` is clamped to |
| `sys_ticrate` | 0.0333333 | an INTERVAL in seconds. Smaller is faster |
| `sv_status_privacy` | 1 | hides client IPs from `status` |
| `sv_weaponstats_file` | `""` | but the shipped example config sets it. See below |
| `sv_curl_defaulturl` | a xonotic.org URL | |
| `g_maplist` | `""` | empty means every map you have |
| `g_maplist_shuffle` | 1 | random |
| `g_antilag` | 2 | server-side hit scan in the past |
| `fraglimit_override` / `timelimit_override` | -1 | -1 = use the map's own value |
| `minplayers` | 0 | bots to fill to |
| `skill` | 8 | lower is easier |
| `g_start_delay` | 15 | seconds before a match begins |
| `hostname` | `Xonotic 0.8.6 Server` | |

`skill`'s built-in description ("0 = easy ... 3 = nightmare (same layout as hard but
monsters fire twice)") is **inherited Quake text about monster layouts** and says nothing
about Xonotic's bots. Ignore it; the default is 8 and lower is easier.

`vid_desktopfullscreen 1` is the least obvious thing about this engine's video: it means
"use the desktop resolution and ignore `vid_width`/`vid_height` entirely". It has to be
turned off before a specific mode means anything.

## Cvars that must be set before the first map

`startmap_dm` is the alias the dedicated build runs once it has finished reading configs.
Xonotic redefines it as:

```
set _sv_init 0; map _init/_init; exec $serverconfig; set _sv_init 1
```

So `server.cfg` is exec'd **after** the first map has already loaded -- which means after
the listen socket is open. Anything that decides how the socket is opened has to be a `+`
argument on the command line instead, because `stuffcmds` runs earlier (see the chain
above). That is `net_address`, `net_address_ipv6` and `port`.

`-basedir` and `-userdir` are startup options with no cvar at all.

`+serverconfig server.cfg` is how the config gets named, and it is exactly what upstream's
own `server/server_linux.sh` does.

## Keeping traffic off the internet

**`sv_public 0`, and not `-1`.** The values are: 1 advertises to the public master servers,
0 answers direct queries only, -1 answers nothing, -2 refuses connections. A LAN server
browser finds servers by broadcasting a query, so -1 would hide the server from the people
sitting next to it. The dedicated build's default is 1.

The engine also carries three built-in masters in `sv_masterextra1..3`
(`dpmaster.deathmask.net`, `dpmaster.tchr.no`, `dpm.dpmaster.org`) alongside the four
settable `sv_master1..4`. With `sv_public 0` none of the six is contacted.

**Weapon telemetry is ON in the shipped example config.** `server/server.cfg` leaves this
line uncommented:

```
sv_weaponstats_file "http://www.xonotic.org/weaponbalance/"
```

which posts server name, IP, gametype, map and per-weapon hit and damage tallies upstream
after every match. The cvar's own default is `""`; it is the example file that turns it on.
Anyone starting from that file inherits it by accident. The same file also uncomments
`sv_vote_gametype 1`, and its example `g_maplist` still names `oilrig`, a map that no longer
exists in 0.8.6.

`sv_curl_defaulturl` defaults to a xonotic.org download URL, used when a joining client is
missing map content. On a network with no route out it only buys a stall while curl waits
for DNS.

## Ports, and the IPv6 hole

26000/udp, inherited from Quake because DarkPlaces speaks a Quake-derived protocol. UDP
only; there is no TCP listener. It does not collide with Quake III's 27960.

**`net_address` only covers IPv4.** With `net_address` set to a LAN address and
`net_address_ipv6` left alone, `ss -lunp` against a running server shows two sockets:

```
UNCONN  127.0.0.1:26123   0.0.0.0:*   xonotic-linux64
UNCONN       [::]:26123      [::]:*   xonotic-linux64
```

The second is every IPv6 address on every interface -- the whole hole the first option just
closed. `cvarlist` explains why: both cvars default to `""`, described as *"if empty, use
default interfaces"*.

There is no option to switch IPv6 off, so the socket will exist either way. Setting
`net_address_ipv6 ::1` points it at loopback, where nothing outside the machine can reach
it:

```
UNCONN  127.0.0.1:26123   0.0.0.0:*
UNCONN      [::1]:26123      [::]:*
```

## The launcher upstream ships

`xonotic-linux-sdl.sh` exists to `cd` into the install directory and to support starting the
game on a separate X server. To do the second job it calls **`netstat`**, which Ubuntu 24.04
does not install by default -- `net-tools` is not a dependency of anything on a stock
desktop. Running the binary directly with `-basedir` does the useful half and has no such
dependency.

## Running it headless, for checking things

The SDL client will start with no display at all, which is how every default in this
document was read:

```bash
SDL_VIDEODRIVER=dummy ./xonotic-linux64-sdl \
    -basedir . -userdir /tmp/probe +cvarlist +quit
```

Output format is `name is "current" ["default"] description`. The dedicated binary takes the
same `+cvarlist +quit`, and its defaults differ from the client's -- `sv_public` most
importantly.

## Sources

- `Xonotic/server/readme.txt` and `Xonotic/server/server.cfg` in the release archive
- `quake.rc`, `default.cfg`, `xonotic-common.cfg`, `xonotic-client.cfg`,
  `xonotic-server.cfg`, `commands.cfg` inside `data/xonotic-20230620-data.pk3`
- `cvarlist` from both shipped Linux binaries, 0.8.6
- <https://xonotic.org/download/> and <https://dl.xonotic.org/xonotic-0.8.6.sha512>
