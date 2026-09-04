# Quake III on Ubuntu: the facts worth not rediscovering

Everything here was verified against Ubuntu 24.04's packages, the installed binaries, or
ioquake3 upstream source. Where a value looks arbitrary, the reason it is not is given.

## Packages

| Package | Component | What it is |
| --- | --- | --- |
| `ioquake3` | universe | The client engine. **Nothing on `$PATH`.** |
| `ioquake3-server` | universe | `ioq3ded` plus the `qagame` modules. |
| `quake3`, `quake3-server` | **multiverse** | Launcher wrappers only, built from `game-data-packager`. |
| `quake3-data` | not in the archive | You would build it locally from your own `pak0.pk3`. |

This repo installs the two universe packages and nothing else. The multiverse wrappers do
only what our systemd unit and launcher script do explicitly, and enabling multiverse is a
system-wide apt change a game playbook has no business making.

## Paths

```
/usr/lib/ioquake3/ioquake3              client binary (NOT on PATH)
/usr/lib/ioquake3/ioq3ded               dedicated server binary (NOT on PATH)
/usr/lib/ioquake3/renderer_opengl{1,2}_x86_64.so
/usr/lib/quake3/base/baseq3/            <- fs_basepath. Game data goes HERE.
/usr/lib/quake3/base/baseq3/*.so        cgame/ui/qagame, symlinked in by the package
~/.q3a/baseq3/                          <- fs_homepath, per user
/var/games/quake3-server/baseq3/        <- fs_homepath for the dedicated server
/etc/apparmor.d/usr.lib.ioquake3.{ioquake3,ioq3ded}
```

`/usr/lib/quake3/base/baseq3` is not an arbitrary pick. The Debian package pre-creates it
with the game modules already symlinked in, and both AppArmor profiles allow reads under
`/usr/lib/quake3/`.

### AppArmor

Both shipped profiles are `flags=(complain)` -- they log rather than block, today. What
they permit:

```
/etc/{openarena,quake3}-server/** r,
/usr/lib/{ioquake3,quake3,openarena,openarena-server}/{,**} mr,
/usr/share/games/{quake3*,openarena}/{,**} r,
owner @{HOME}/.{openarena,q3a}/{,**} rwk,
owner /var/games/{openarena,quake3}-server/** rwk,     # ioq3ded only
```

Every path this repo writes to is inside that set. Staying there means the day somebody
switches the profiles to enforce, nothing breaks.

### `exec` resolves against the game's virtual filesystem

Not against the real one. A config at `/etc/anything/server.cfg` **cannot** be reached by
`+exec` -- it has to sit under `<fs_homepath|fs_basepath>/baseq3/`. This is why the
dedicated server's config is at `/var/games/quake3-server/baseq3/server.cfg` and the
Debian packaging resorts to symlinking `/etc/quake3-server` into the search path.

## Config file precedence

Three files, and knowing the order is the difference between a setting sticking and
vanishing:

| File | Written by | Read |
| --- | --- | --- |
| `q3config.cfg` | **the engine**, on every clean exit | first |
| `autoexec.cfg` | Ansible, every run | after `q3config.cfg`, so it wins |
| `lanparty-local.cfg` | created once by Ansible, then yours | last, `exec`'d from `autoexec.cfg` |

Consequence: **changes made in the in-game menus do not persist.** They land in
`q3config.cfg` and are overridden on the next launch. That is deliberate. Personal
settings belong in `lanparty-local.cfg`; fleet-wide settings belong in
`group_vars/all.yml`.

## Cvars that are command-line only

Setting these in a cfg silently does nothing.

| cvar | Why |
| --- | --- |
| `dedicated` | `CVAR_INIT`. `1` = LAN and never sends a master-server heartbeat. `2` = public. |
| `net_ip`, `net_port` | `CVAR_LATCH` |
| `com_hunkMegs` | `CVAR_LATCH` |
| `fs_game`, `fs_basepath`, `fs_homepath` | `CVAR_INIT` |

`sv_maxclients`, `g_gametype`, `r_mode`, `r_customwidth` and `r_customheight` are also
`CVAR_LATCH` -- settable in a cfg, but only effective after a map load or `vid_restart`.

## Keeping traffic off the internet

Four separate things reach out by default. All four are closed:

| Default behaviour | Closed by |
| --- | --- |
| Server heartbeats to `master.quake3arena.com`, `directory.ioquake3.org` | `dedicated 1`, plus `sv_master1..5 ""` |
| Server validates each joining client against `authorize.quake3arena.com` | `sv_strictAuth 0` -- **without this, joins stall with no internet** |
| Client fetches the message of the day from `updates.quake3arena.com` | `cl_motd 0` |
| Server listens on every interface | `+set net_ip <lan address>` |

## Ports

All UDP.

| Port | |
| --- | --- |
| **27960** | game server (`net_port`) |
| 27960-27963 | the range the LAN browser scans -- **a server outside it is invisible** |
| 27950 | master server (outbound) |
| 27951 / 27952 | update / CD-key authorize (outbound) |

Clients need no inbound rule; they bind an ephemeral source port.

### How the LAN browser finds servers, and why an overlay breaks it

This repo runs entirely on the physical LAN and never on an overlay, so none of the
following is a live constraint -- it is written down because it is the reason for that
choice, and because a machine here may still be running Tailscale for unrelated work.

The client sends `getinfo` as an **IPv4 subnet broadcast** to 27960-27963, twice, plus an
IPv6 multicast. Servers answer with `infoResponse`, filtered by `com_gamename`.

Broadcast does not cross a router, a VLAN boundary, or a layer-3 overlay. Tailscale is a
point-to-point WireGuard mesh with no broadcast domain, so the probe reaches nobody --
tracked upstream as tailscale#11134, #8884, #15602, all still feature requests. Direct
`+connect` over the tailnet does work, since the game protocol itself is plain unicast
UDP; it is only discovery that dies.

One further wrinkle: `Sys_IsLANAddress()` does not classify `100.64.0.0/10` as LAN, so
`sv_lanForceRate` never kicks in for a tailnet client and it gets its own clamped `rate`
instead of the full pipe. Another reason gameplay stays on the physical LAN.

## Client tuning: defaults, clamps, and what is worth changing

| cvar | Default | LAN | Note |
| --- | --- | --- | --- |
| `snaps` | 20 | `= sv_fps` | Clamped to `[1, sv_fps]`. Asking for more than the server runs silently gives you less. |
| `cl_maxpackets` | 30 | 125 | Hard-clamped to `[15, 125]`. |
| `rate` | 25000 | 25000 | Moot on a real LAN: `sv_lanForceRate 1` overrides it for same-subnet clients. |
| `cl_timenudge` | 0 | 0 | Trades a deliberate delay for smoothness. Nothing to smooth at sub-millisecond RTT. |
| `cl_packetdup` | 1 | 0 | Duplicate packets for loss resilience; unnecessary at 0% loss. |
| `com_maxfps` | 85 | **125** | Jump height and strafe acceleration are framerate-coupled. 125 is canonical. |
| `r_swapInterval` | 0 | 0 | Vsync off: tearing, but up to a frame less input latency. |
| `r_finish` | 0 | **0** | `1` blocks the CPU until the GPU finishes each frame. Sometimes suggested as a smoothness fix; it is a latency tax. |
| `cl_renderer` | `opengl2` | `opengl1` | opengl2 compiles shaders on first map load -- a hitch exactly when everyone spawns. |
| `r_textureMode` | `GL_LINEAR_MIPMAP_NEAREST` | `..._LINEAR` | Trilinear. Note the capital M in the cvar name. |
| `r_mode` | -2 | -1 + custom | `-2` = desktop resolution, `-1` = use `r_customwidth`/`r_customheight`. |
| `r_subdivisions` | 4 | 1 | Curve tessellation. The default visibly facets arches and pipes. |

### Detecting the native resolution without a display

```sh
for c in /sys/class/drm/card*-*/; do
  [ "$(cat "$c/status")" = connected ] || continue
  head -1 "$c/modes"     # first line is the preferred (native) mode
  break
done
```

Chosen over `xrandr` because it needs no X display, no extra package, and works over SSH
with nobody logged in -- which is how every machine except the control node is
provisioned.

## Server notes

- `sv_fps` default 20 is a dial-up-era value. 40 for LAN; it is also the ceiling on
  clients' `snaps`.
- `sv_pure 1` rejects clients whose `.pk3` set differs. Safe here only because Ansible
  pushes byte-identical data everywhere.
- Map rotation is a `vstr` chain. `map` must come **last** in each `set` string because it
  blocks, and the kickoff `vstr` must be the final line of the file. `g_gametype` is
  re-set inside every entry because it is `CVAR_LATCH`.
- `vm_game 0` loads the native `qagame` `.so` instead of the QVM bytecode interpreter.
  The interpreter needs a writable+executable page, so `MemoryDenyWriteExecute` cannot be
  used with it.
- Exit code 72 means "no game data" -- hence `RestartPreventExitStatus=72`, since
  restarting will not conjure a `pak0.pk3`.

## Game data

`pak0.pk3` is retail id Software data: **479,493,658 bytes**, MD5
`1197ca3df1e65f3c380f8abc10ca43bf`. Not redistributable. Sources: a retail CD, Steam
appid 2200, or GOG `quake_iii_gold`.

`pak1.pk3` through `pak8.pk3` from the 1.32 point release **are** freely redistributable.
id's repack: <https://files.ioquake3.org/quake3-latest-pk3s.zip> (behind an EULA click on
<https://ioquake3.org/extras/patch-data/>).

This repo blocks `*.pk3`, `baseq3.zip` and `baseq3/` in `.gitignore`, and pushes the
archive from the control node to every machine so only one copy has to exist.

## Sources

- <https://ioquake3.org/help/sys-admin-guide/>, <https://ioquake3.org/help/players-guide/>
- <https://packages.ubuntu.com/noble/ioquake3>, `.../ioquake3-server`
- <https://manpages.debian.org/unstable/ioquake3/ioquake3.6.en.html>
- <https://salsa.debian.org/games-team/game-data-packager/-/raw/master/data/quake3.yaml>
- <https://github.com/ioquake/ioq3>
- Tailscale broadcast/multicast: tailscale/tailscale#11134, #8884, #15602
