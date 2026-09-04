# lanparty

Ansible for running a LAN party in an office, over the office LAN and nothing else.

**One address per machine, used for both jobs.** Ansible reaches each machine at its
physical LAN address to install things, and the game server binds that same address for
clients to connect to. Input packets ride the office switch. There is no overlay network,
no VPN, and no second address that could be used by mistake.

Game-agnostic. Two games ship today -- **Quake III Arena** (the default) and **Xonotic** --
and switching between them is one variable:

```bash
./bootstrap.sh                            # Quake III Arena
./bootstrap.sh -e lanparty_game=xonotic   # Xonotic
```

Nothing in `site.yml` names either of them. See [Adding a game](#adding-a-game).

---

## Quick start

### Before you start

- Every machine on **one switch, one subnet**. No router or VLAN between them.
- Ubuntu on each, with `openssh-server` installed on the ones you are not sitting at.
- A copy of Quake III's game data on the **first machine only** -- a Steam or GOG install,
  a retail disc, or `~/Downloads/baseq3.zip`. Ansible copies it to everyone else.
  No copy anywhere? That is one extra command: see [No game data](#no-game-data).

### Step 1 -- the first machine

This is the machine you run Ansible from, and it is also the game server.

Paste this exactly as it is. It fills in your own hostname and login, so there is
**nothing to edit**:

```bash
git clone git@github.com:chris24sahadeo/lanparty.git ~/lanparty
cd ~/lanparty

cat > inventory/hosts.yml <<YAML
all:
  vars:
    ansible_user: $USER
    ansible_host: "{{ lan_ip | default(inventory_hostname) }}"
  children:
    game_server:
      hosts:
        $(hostname):
          ansible_connection: local
    game_clients:
      hosts:
        $(hostname):
          ansible_connection: local
YAML

./bootstrap.sh --tags preflight
./bootstrap.sh
```

What those two commands do:

| | |
| --- | --- |
| `./bootstrap.sh --tags preflight` | checks the network only. Changes nothing, needs no sudo. |
| `./bootstrap.sh` | installs everything. Asks for your sudo password once. |

Now type **`q`**. You are playing.

### Step 2 -- every other PC

Do this once per machine. On the **new PC**:

```bash
sudo apt install -y openssh-server
ip -4 -br addr
```

Note its address on the office network -- the `192.168.x.x` one, not `127.0.0.1` and not
anything on `docker0`.

Back on the **first machine**, run this and answer three questions:

```bash
cd ~/lanparty
./add-machine.sh
```

```
==> Adding a machine to lanparty
Name for this machine (any label): joes-laptop
LAN address for joes-laptop (its 192.168.x.x): 192.168.0.51
SSH login on joes-laptop [chris]:
==> Checking joes-laptop at 192.168.0.51
  ok responds to ping
  ok ssh key login works
  ok inventory parses, and joes-laptop is in game_clients with lan_ip 192.168.0.51
Run the network check now? (changes nothing, no sudo) [Y/n]
Provision joes-laptop now? (asks for a sudo password) [Y/n]
```

It edits `inventory/hosts.yml` for you, and it will not let you add a machine that is
unreachable, already listed, or has an address that cannot work. If SSH key login is not
set up yet it offers to run `ssh-copy-id` there and then.

Say yes to the last question and you are done -- type **`q`** on the new PC.

<details>
<summary>Doing it by hand instead</summary>

`add-machine.sh` only writes two lines. Add them under `game_clients:` yourself, lined up
with the host already there:

```yaml
        someones-laptop:
          lan_ip: 192.168.0.51
```

Add `ansible_user: someone` under it if that machine has a different login. Then:

```bash
ssh-copy-id someone@192.168.0.51
./bootstrap.sh --ask-become-pass
```

`--ask-become-pass` is needed here and not in step 1: it asks once and uses the same
password on every remote machine. If a machine has a different password, give that one
passwordless sudo instead.

</details>

### Playing

```
q                 join the server
q --menu          main menu -- this is where you change settings
q --windowed      join, but windowed
q --help          everything else
```

---

## If something goes wrong

| What you see | What it means |
| --- | --- |
| `changed=0` | Nothing needed doing. That is what a correct second run looks like. |
| `PREFLIGHT WARNINGS ... is wireless` | Plug that machine into the switch. WiFi jitter is the worst thing you can do to this. |
| `sudo: a password is required` | Re-run with `--ask-become-pass`. |
| `No interface on this machine holds its lan_ip` | The `lan_ip` in `inventory/hosts.yml` is wrong. Check `ip -4 -br addr` on that machine. `./add-machine.sh` refuses to write a bad one in the first place. |
| `No Quake III game data found` | See [No game data](#no-game-data) below. |

### No game data

Only happens on a machine with no copy anywhere. `pak0.pk3` is retail data this repo
cannot ship, so it is fetched from Google Drive instead -- once, then it is cached in
`.gamedata/` and later runs are offline:

```bash
sudo apt install -y rclone     # or: brew install rclone
rclone config                  # add a Google Drive remote named personal-gdrive
./bootstrap.sh
```

Already own the game? Nothing to do. A Steam, GOG, mounted-disc or `~/Downloads/baseq3.zip`
copy is found automatically and used in preference to the download. Full search order:
[Game data](#game-data).

### Running fewer machines

`bootstrap.sh` passes every argument through to `ansible-playbook`, so `--check`, `--diff`,
`--limit` and `--tags` all work. Tags: `preflight`, `host`, `server`, `client`.

Using `--limit`, **include the server machine too** -- `--limit new-pc,my-pc`. The client
tasks read the server's address, and that is only available for machines in the run.

---

## Why the LAN and nothing else

An earlier version of this repo deployed over a [Tailscale](https://tailscale.com) tailnet
and played over the LAN. It worked, and it was two addresses per host that must never be
interchanged -- which is one paste away from a party that silently plays through a
WireGuard tunnel. Running everything on the LAN removes the whole class of mistake, and
avoids two costs that an overlay imposes on exactly the wrong traffic:

1. **Encryption and MTU overhead on the packets that can least afford it.** Even when two
   overlay peers find a direct path over the same switch, every packet is encrypted,
   decrypted, and fitted into a smaller MTU (Maximum Transmission Unit). That is a fine
   trade for a file copy and a bad one for a rocket jump.
2. **The in-game LAN server browser stops working.** Quake III finds local servers by
   sending an IPv4 subnet broadcast to UDP 27960-27963. A layer-3 mesh has no broadcast
   domain, so the probe goes nowhere. You would be handing out IP addresses by hand all
   evening.

What it costs: **a machine that is not on this LAN cannot be provisioned.** Everyone has
to be in the room and plugged in before Ansible can reach them, where before you could
prepare a laptop from anywhere. At a party, that is not a real cost.

Tailscale may still be installed on these machines for unrelated reasons -- this repo does
not manage it either way. `roles/lan_preflight` checks, per machine, that nothing has
quietly moved game traffic onto it.

---

## The inventory

`inventory/hosts.yml` carries **one address per machine**, `lan_ip`, doing both jobs:

| job | how it is used |
| --- | --- |
| deployment | Ansible SSHes to it |
| gameplay | the server binds it; clients connect to it |

```yaml
game_clients:
  hosts:
    someones-laptop:
      lan_ip: 192.168.1.41
```

That is the whole entry. The two are kept identical by construction rather than by
discipline -- the inventory's group vars set

```yaml
ansible_host: "{{ lan_ip | default(inventory_hostname) }}"
```

so there is no separate deploy address to get wrong.

`lan_ip` is optional. Omit it and Ansible connects to the inventory hostname instead, which
works if that name resolves (mDNS `.local`, your router's DNS, an `/etc/hosts` entry); the
game address then falls back to the host's primary IPv4 address, right for any machine with
one NIC (Network Interface Card). Set `lan_ip` explicitly on anything multi-homed --
`roles/lan_preflight` fails a machine whose `lan_ip` no interface actually holds, because
the dedicated server binds that address and will not start otherwise.

Everyone must be on **one flat layer-2 segment**. Broadcast does not cross a router or a
VLAN boundary, so the server browser stops working the moment machines are on different
subnets.

### What each machine needs before Ansible can reach it

This repo installs none of it -- see [What this repo will not touch](#what-this-repo-will-not-touch).

- **`openssh-server` running and reachable on the LAN**, with the control node's public key
  in `~/.ssh/authorized_keys`. This is the part that changed when the tailnet went away:
  the SSH path is now the office network, so a machine that is not plugged in is a machine
  you cannot provision.
- **`python3`** -- stock on Ubuntu.
- The login user in `sudo`. Set `ansible_user` per host if it differs from the group value.

### Adding a machine

```bash
ssh-copy-id chris@192.168.1.41           # once per machine, from the control node
$EDITOR inventory/hosts.yml              # add it under game_clients with its lan_ip
./bootstrap.sh --tags preflight          # no sudo, changes nothing
./bootstrap.sh --ask-become-pass
```

Then `q` on that machine. Two things to know about narrowing the run with `--limit`:

- **Include the server host.** The client and host roles read the server's address out of
  `hostvars`, and if `lan_ip` is not set explicitly there they fall back to its gathered
  facts -- which only exist for hosts in the play. `--limit new-pc,<server>` is safe;
  `--limit new-pc` alone can fail on that lookup. Re-running against an already-provisioned
  server is idempotent and reports `changed=0`.
- **`--ask-become-pass` sends one password to every host.** `bootstrap.sh` only adds the
  flag when the *control node's* own sudo needs a password, so if yours is already warm the
  remote `apt` task fails instead. Pass it yourself, and if the new machine's password
  differs, give that host passwordless sudo or a vaulted `ansible_become_password`.

---

## Game data

`pak0.pk3` is retail id Software data. It is not redistributable, this repo is public, and
`.gitignore` blocks `*.pk3` and `baseq3.zip` so it cannot be committed by accident.

**Nothing needs configuring.** The control node is searched, in this order, and the first
hit wins -- and if none of them has it, it is downloaded from Google Drive. See
[If the control node has no copy at all](#if-the-control-node-has-no-copy-at-all).

| | |
| --- | --- |
| `<repo>/.gamedata/baseq3.zip` | a copy kept with the repo -- gitignored |
| `~/Downloads/baseq3.zip`, `~/baseq3.zip`, `~/Games/baseq3.zip` | a zip containing `baseq3/*.pk3` |
| `<repo>/.gamedata/baseq3/` | loose `.pk3` files |
| `~/.steam/steam/steamapps/common/Quake 3 Arena/baseq3` | Steam, appid 2200 -- no copying needed |
| `~/.local/share/Steam/...`, `~/.steam/root/...` | other Steam layouts |
| `~/GOG Games/Quake III Arena/baseq3` | GOG |
| `/media/$USER/*`, `/mnt/*`, other-drive Steam libraries | a mounted retail CD |

Find nothing and the run stops with that list, rather than half-installing. **Only the
control node needs a copy** -- Ansible pushes it to every other machine, so one copy in
the room is enough.

Override the search with `lanparty_quake3_baseq3_src`. Enforce a specific archive with
`lanparty_quake3_baseq3_sha256`, empty by default because several legal copies exist and
a checksum that rejects a good one is worse than no checksum.

### If the control node has no copy at all

A brand-new machine finds nothing above, so it fetches the archive with **rclone** from
`lanparty_quake3_baseq3_rclone_src` (`group_vars/all.yml`), default
`personal-gdrive:lanparty/baseq3.zip`. It lands in `.gamedata/baseq3.zip`, which is both
the first path the search looks at and gitignored -- so it downloads once, every later run
finds it locally, and the retail data still never goes near git.

Setting up a new control node is therefore:

```bash
brew install rclone && rclone config     # add your Google Drive remote, once per machine
git clone git@github.com:chris24sahadeo/lanparty.git ~/lanparty
cd ~/lanparty && ./bootstrap.sh
```

Three things worth knowing:

- **This repo does not install rclone.** It is a Homebrew package on this workstation and
  Homebrew belongs to layer 2 -- see [What this repo will not touch](#what-this-repo-will-not-touch).
  A control node without it gets told how to set it up and the run stops there.
- **The remote name is per-machine.** It lives in `~/.config/rclone/rclone.conf`, which this
  repo does not manage either. Change `lanparty_quake3_baseq3_rclone_src` to match your own
  remote, or set it to `""` to turn the fallback off.
- **rclone, not `get_url`, for a specific reason.** Google Drive does not serve a 637 MB
  file over plain HTTP -- anything past roughly 100 MB gets an HTML virus-scan interstitial
  instead of the bytes. `get_url` would write that HTML to `.gamedata/baseq3.zip` and the
  failure would surface much later as an unzip error that says nothing about the cause.
  rclone handles the interstitial, resumes a broken transfer, and verifies the result
  against Drive's own MD5 (Message Digest 5).

The data itself is still **not** in this repo and will not be: it is retail id Software
data with no redistribution licence, this repo is public, `pak0.pk3` is 479 MB against
GitHub's 100 MB file limit, and Git LFS's free tier (1 GB storage, 1 GB bandwidth a month)
is about one clone. Drive holds one private copy; Ansible fetches it to one control node
and pushes it to everyone else.

---

## How the LAN guarantee is actually enforced

Five mechanisms. Each is independently checkable, which is the point -- a comment claiming
traffic stays local is not worth anything.

| # | Mechanism | Where | Verify |
| --- | --- | --- | --- |
| 1 | Server binds one address, so it listens on the LAN interface and no other -- not on `tailscale0` or any other VPN interface the machine runs | `+set net_ip` in the systemd unit | `ss -lunp \| grep 27960` shows the LAN address, not `0.0.0.0` |
| 2 | `dedicated 1` (LAN), never `2` (public) -- `1` never sends a master-server heartbeat | systemd unit; it is `CVAR_INIT`, so command line only | `ss -tunp \| grep ioq3ded` shows no public flow |
| 3 | `sv_master1..5` blanked and `sv_strictAuth 0` | `server.cfg` | without `sv_strictAuth 0` the server calls `authorize.quake3arena.com` on every join and stalls with no internet |
| 4 | Clients launch with `+connect <server lan_ip>` | `/usr/local/bin/lanparty-quake3` | read the script |
| 5 | `/etc/hosts` pins `lanparty-server` to the LAN address | `roles/game_host` | stops Tailscale MagicDNS, mDNS or a router's DNS answering the name with some other address |

`roles/lan_preflight` re-checks 1-4 from each machine's point of view: which interface the
traffic would leave on, whether any interface actually holds the machine's `lan_ip`,
whether that interface is wireless, whether either address is in the `100.64.0.0/10` range
an overlay would hand out, and the worst round trip out of 20 pings.

It **warns and continues** by default, because a first run happens while machines are
still being carried in. Set `lanparty_preflight_strict: true` on party morning and every
finding becomes a hard stop.

---

## Playing, and changing settings

```
q                 join the server immediately
q -m, --menu      start at the main menu instead -- this is the one for changing settings
q -w, --windowed  join, but windowed
q -s HOST[:PORT]  join a different server
q -h, --help      the above, plus where settings live
```

Anything else passes straight to the engine: `q --menu +set cl_renderer opengl2`.

### Menu changes do not stick, on purpose

Three config files, read in this order. Later ones win:

| File | Written by | Edit it? |
| --- | --- | --- |
| `~/.q3a/baseq3/q3config.cfg` | **the engine**, on every clean exit | No -- it is a dump, not a source |
| `~/.q3a/baseq3/autoexec.cfg` | Ansible, **overwritten every run** | No -- change `group_vars/all.yml` |
| `~/.q3a/baseq3/lanparty-local.cfg` | created once by Ansible, then **yours** | Yes |

So anything you change through Setup > System lands in `q3config.cfg` and is overridden on
the next launch. That is the whole reason the shipped config is called `autoexec.cfg` --
see `docs/quake3-setup-guide.md`.

Which means:

- **Try something now:** the in-game console (`~`). Applies immediately, forgotten on quit.
- **Keep it, just for you:** `~/.q3a/baseq3/lanparty-local.cfg`. Ansible creates it once and
  never touches it again. Reload without restarting: `/exec lanparty-local.cfg`.
- **Keep it, for every machine:** `group_vars/all.yml`, then re-run `./bootstrap.sh`.
  The knobs are `lanparty_quake3_gfx_cvars`, `lanparty_quake3_lan_cvars`,
  `lanparty_quake3_renderer`, `lanparty_quake3_width` / `_height`.

---

## Adding a game

A game is one manifest plus roles that satisfy its contract. `site.yml` never names a
game.

1. Write `games/<id>.yml`. Copy `games/quake3.yml`; the keys are documented there.
2. Write the roles it names -- typically `<id>_common`, `<id>_server`, `<id>_client`.
3. Set `lanparty_game: <id>` in `group_vars/all.yml`, or pass `-e lanparty_game=<id>` for
   one run.

Firewall handling, `/etc/hosts`, service naming and the LAN path check are generic and
come for free.

The two that exist:

| | `lanparty_game` | port | game data |
| --- | --- | --- | --- |
| Quake III Arena | `quake3` | 27960/udp | retail, must be supplied -- see [Game data](#game-data) |
| Xonotic | `xonotic` | 26000/udp | free, downloaded and checksummed automatically |

Their ports do not collide, so both can be provisioned on one fleet and both servers can
run at once. Only `lanparty_game` decides which one a given run touches.

---

## What this repo will not touch

This workstation already runs two other Ansible trees, and this is the third:

| | tree | scope |
| --- | --- | --- |
| layer 1 | a work provisioning repo | the dev machine itself |
| layer 2 | `~/ansible` | personal workstation |
| layer 3 | this repo | LAN party |

Hands off, because something else already owns them: Tailscale itself, `openssh-server`
and `authorized_keys`, Docker, Homebrew, anything in `~/.local/bin`, MIME associations and
`.desktop` defaults, `~/.claude`, chezmoi-managed dotfiles. No apt source or PPA is added
by anything here.

Tailscale stays on that list even though the party no longer uses it. This repo dropping
the tailnet as its deploy plane is not a reason to uninstall a daemon another tree
installed for its own purposes -- `roles/lan_preflight` simply checks that it is not in the
game's path.

**Firewall policy: open ports on a firewall that is already running, never turn one on.**
Enabling ufw on a machine whose owner did not choose it is a good way to break their
workstation from a game playbook -- most obviously on a Docker host, where ufw does not
filter Docker's own iptables chain.

Isolation is enforced, not promised. `ansible.cfg` redirects `collections_path`,
`local_tmp` and `roles_path` in-tree; `bootstrap.sh` exports `ANSIBLE_CONFIG` and builds
its own virtualenv rather than touching the shared `~/.local/bin/ansible*` shims.
`test/container.sh` proves `~/.ansible` is unchanged after a full run.

---

## Notes on Xonotic specifically

Full engine reference: [`docs/xonotic-reference.md`](docs/xonotic-reference.md). The short
version, and how it differs from the other game:

- **No game data problem at all.** Xonotic is free software with freely licensed art, so
  `roles/xonotic_common` downloads the official 1.18 GB release from `dl.xonotic.org` and
  verifies it against the SHA-512 upstream publishes. No search, no rclone, nothing to
  carry into the room. It is still gitignored -- for size, not licensing.
- **Not from apt.** There is no `xonotic` package in Ubuntu 24.04 in any component;
  `darkplaces` in universe is the bare Quake engine and cannot play it. Flathub has a build,
  but adding a flatpak remote is a system-wide change to a machine's software sources, which
  is the same rule this repo obeys for apt. So: upstream's archive, unpacked to
  `/opt/Xonotic`. Seven apt packages are still installed -- the shared libraries the
  binaries dlopen, where a missing one is a silently degraded game rather than an error.
- **`sv_public 0`, never `-1`.** 0 stops the server advertising to the public master
  servers but still answers direct queries -- which is what a LAN server browser sends. `-1`
  would hide it from the people sitting next to it. The dedicated build defaults to 1.
- **`net_address` only binds IPv4.** Set it alone and the engine still opens a second socket
  on `[::]` -- every IPv6 address on every interface, including a VPN's. The unit also passes
  `net_address_ipv6 ::1`; there is no way to turn the socket off, so it is pointed at
  loopback. Checked with `ss -lunp`, not assumed.
- **Weapon telemetry ships switched on.** Upstream's example `server.cfg` leaves
  `sv_weaponstats_file` pointed at xonotic.org, which posts server name, IP, map and
  per-weapon damage tallies after every match. This repo writes its own config from scratch
  rather than starting from that file, and blanks the cvar explicitly.
- **`rate` is a command, not a cvar.** `seta rate 1000000` silently creates a new cvar and
  changes nothing; the real setting lives in `_cl_rate` and is written by the bare `rate`
  command.
- **`sys_ticrate` is an interval, so smaller is faster.** Xonotic ships 30 Hz with its own
  comment saying 60 "would be ideal, but kills home routers". A LAN has no router in the
  path, so we take 60.
- The client config is installed as **`autoexec.cfg`**, and here that is not a workaround:
  the shipped data pk3 contains an `autoexec.cfg` that says, in full, *"placeholder file, is
  replaced by autoexec.cfg in user home directory"*. `config.cfg` is rewritten by the engine
  on every quit, exactly like Quake III's `q3config.cfg`.
- Launch with `x` (or `lanparty-xonotic`). `x --help` explains where settings live.

---

## Notes on Quake III specifically

- Engine is `ioquake3` + `ioquake3-server` from Ubuntu **universe**. The multiverse
  `quake3` / `quake3-server` packages are only launcher wrappers, and enabling multiverse
  is a system-wide apt change this repo has no business making. Neither package puts
  anything on `$PATH`; the binaries are `/usr/lib/ioquake3/{ioquake3,ioq3ded}`.
- Game data goes in `/usr/lib/quake3/base/baseq3/`, which the Debian package pre-creates
  and both shipped AppArmor profiles allow reads under.
- The client config is installed as **`autoexec.cfg`**, not `q3config.cfg`. The engine
  rewrites `q3config.cfg` from live cvar state on every clean exit, so a tuned config
  under that name survives exactly until the first player quits. `autoexec.cfg` is
  exec'd after it on every start and therefore wins.
- `sv_pure 1` is on. Safe because Ansible pushes byte-identical data everywhere, and it is
  what stops one person with a doctored pak having different hitboxes.
- Server tick is `sv_fps 40` and clients ask for `snaps 40`. The stock 20 is a dial-up
  default; the server clamps `snaps` to `sv_fps`, so asking for more than the server runs
  silently gives you less.
- **Every machine renders at 1920x1080**, not at its own native mode, and clamps down only
  where a panel cannot show 1080p. One resolution means what you learn on one machine
  transfers to the next; it also stops a docked laptop quietly being configured for its 4K
  monitor. `lanparty_quake3_width` / `_height`, both `""` to go back to per-machine
  detection.
- **`com_maxfps 125` and `pmove_fixed 1` are doing different jobs.** Quake III integrates
  movement in whole milliseconds once per rendered frame, so jump height and strafe
  acceleration depend on frame rate; 125 is canonical because 1000/125 is exactly 8 ms.
  But `com_maxfps` is only a request, and a laptop that dips to 90 in a firefight gets
  different physics from the machine beside it. `pmove_fixed 1` with `pmove_msec 8` makes
  the server step movement at a fixed 125 Hz for everyone regardless of frame rate -- the
  same physics, now guaranteed. It costs up to 8 ms of input quantisation, which is the
  trade this repo makes on purpose for mismatched party hardware. `lanparty_quake3_pmove_fixed: 0`
  restores stock behaviour. See [`docs/quake3-reference.md`](docs/quake3-reference.md).
