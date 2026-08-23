# lanparty

Ansible for running a LAN party in an office where every machine is on a
[Tailscale](https://tailscale.com) tailnet.

**Tailscale is the deploy plane. The game is not on it.** Ansible reaches each machine
over its tailnet address to install things; the game server binds the machine's *physical*
LAN address and clients connect to that. Input packets ride the office switch and never
enter the WireGuard tunnel.

Game-agnostic: Quake III Arena is the first game, not the only one.

---

## Why not just play over Tailscale

It would work, and it would be worse in two specific ways.

1. **Encryption and MTU overhead on the packets that can least afford it.** Even when two
   Tailscale peers find a direct path over the same switch, every packet is encrypted,
   decrypted, and fitted into a smaller MTU (Maximum Transmission Unit). That is a fine
   trade for a file copy and a bad one for a rocket jump.
2. **The in-game LAN server browser stops working.** Quake III finds local servers by
   sending an IPv4 subnet broadcast to UDP 27960-27963. Tailscale is a layer-3 mesh with
   no broadcast domain, so the probe goes nowhere. You would be handing out IP addresses
   by hand all evening.

`roles/lan_preflight` checks, per machine, that this has actually been avoided.

---

## Quick start

```bash
git clone git@github.com:chris24sahadeo/lanparty.git ~/lanparty
cd ~/lanparty

# 1. Point the game-data variable at your copy of the Quake III data.
#    See "Game data" below -- it is not, and cannot be, in this repo.
$EDITOR group_vars/all.yml

# 2. List the machines. One server, N clients, two addresses each.
$EDITOR inventory/hosts.yml

# 3. Check the network before installing anything. Changes nothing.
./bootstrap.sh --tags preflight

# 4. Provision everything.
./bootstrap.sh
```

Then on any client: **`q`**, or the longer `lanparty-quake3`, or "Quake III Arena (LAN
party)" in the applications menu. The short name is a symlink in `/usr/local/bin` rather
than a shell alias -- so it works in any shell, over ssh, and from the desktop entry, and
nothing has to write into your `~/.zshrc`. Change it with `lanparty_quake3_alias`, or set
that to `""` to skip it.

`bootstrap.sh` builds an in-tree virtualenv on first run and passes every argument through
to `ansible-playbook`, so `--check`, `--diff`, `--limit`, `--tags` all work.

Useful tags: `preflight`, `host`, `server`, `client`.

---

## The inventory

`inventory/hosts.yml` carries **two addresses per machine and they are never
interchanged**:

| key | range | used for |
| --- | --- | --- |
| `ansible_host` | `100.64.0.0/10` (tailnet) | deployment only -- SSH, which is not latency sensitive and works before anyone is in the room |
| `lan_ip` | e.g. `192.168.x.x` | gameplay only -- what the server binds and clients connect to |

`lan_ip` is optional. Omitted, it defaults to the host's primary IPv4 address, which is
right for any machine with one NIC (Network Interface Card). Set it explicitly on anything
multi-homed.

```yaml
game_clients:
  hosts:
    someones-laptop:
      ansible_host: 100.64.0.2        # tailnet -- DEPLOY ONLY
      lan_ip: 192.168.1.41            # physical LAN -- GAMEPLAY
```

Everyone must be on **one flat layer-2 segment**. Broadcast does not cross a router or a
VLAN boundary, so the server browser stops working the moment machines are on different
subnets.

---

## Game data

`pak0.pk3` is retail id Software data. It is not redistributable, this repo is public, and
`.gitignore` blocks `*.pk3` and `baseq3.zip` so it cannot be committed by accident.

Point `lanparty_quake3_baseq3_src` at a zip containing `baseq3/pak0.pk3`, taken from a
retail CD, a Steam install (appid 2200), or GOG. **Only the control node needs it** --
Ansible pushes it to every machine, so nobody carries a CD around the office.

Set `lanparty_quake3_baseq3_sha256` to match, or `""` to skip the check. Getting this
wrong fails the run with a written explanation rather than producing a server nobody can
join.

---

## How the LAN guarantee is actually enforced

Five mechanisms. Each is independently checkable, which is the point -- a comment claiming
traffic stays local is not worth anything.

| # | Mechanism | Where | Verify |
| --- | --- | --- | --- |
| 1 | Server binds one address, so it does not listen on `tailscale0` at all | `+set net_ip` in the systemd unit | `ss -lunp \| grep 27960` shows the LAN address, not `0.0.0.0` |
| 2 | `dedicated 1` (LAN), never `2` (public) -- `1` never sends a master-server heartbeat | systemd unit; it is `CVAR_INIT`, so command line only | `ss -tunp \| grep ioq3ded` shows no public flow |
| 3 | `sv_master1..5` blanked and `sv_strictAuth 0` | `server.cfg` | without `sv_strictAuth 0` the server calls `authorize.quake3arena.com` on every join and stalls with no internet |
| 4 | Clients launch with `+connect <server lan_ip>` | `/usr/local/bin/lanparty-quake3` | read the script |
| 5 | `/etc/hosts` pins `lanparty-server` to the LAN address | `roles/game_host` | stops MagicDNS resolving the hostname to the tailnet address |

`roles/lan_preflight` re-checks 1-4 from each machine's point of view: which interface the
traffic would leave on, whether that interface is wireless, whether either address is in
the tailnet range, and the worst round trip out of 20 pings.

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
3. Set `lanparty_game: <id>` in `group_vars/all.yml`.

Firewall handling, `/etc/hosts`, service naming and the LAN path check are generic and
come for free.

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

**Firewall policy: open ports on a firewall that is already running, never turn one on.**
Enabling ufw on a machine whose owner did not choose it is a good way to break their
workstation from a game playbook -- most obviously on a Docker host, where ufw does not
filter Docker's own iptables chain.

Isolation is enforced, not promised. `ansible.cfg` redirects `collections_path`,
`local_tmp` and `roles_path` in-tree; `bootstrap.sh` exports `ANSIBLE_CONFIG` and builds
its own virtualenv rather than touching the shared `~/.local/bin/ansible*` shims.
`test/container.sh` proves `~/.ansible` is unchanged after a full run.

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
