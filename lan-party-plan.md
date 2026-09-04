# LAN Party Provisioning Plan — Ubuntu on Framework 13

**Audience:** Claude Code, running locally on the machines being provisioned.
**Goal:** Turn N × Framework 13 laptops running Ubuntu into a working LAN-party fleet for a
vetted set of games, with zero dependence on the venue's internet uplink during the event.

---

## 0. Read this first (agent orientation)

- This is a **plan**, not a spec you must follow blindly. If a command fails, diagnose it;
  do not fabricate success.
- **You cannot install proprietary games without the user's credentials and license.**
  Steam login, disc dumps, and MW2 ownership are all human-in-the-loop steps. Your job is
  everything around them: dependencies, config, firewall, scripts, verification.
- **Idempotency is mandatory.** Every script you write must be safe to re-run. The user will
  run these across many machines, some partially configured.
- **Never `sudo rm -rf` a path built from an unvalidated variable.** Guard all destructive ops.
- Do not download game assets from third-party mirrors. If an asset is missing, stop and
  report which file the human must supply.

### Ask the user before Phase 1

1. How many laptops, and which CPU generation each (`lspci | grep -i vga` → Iris Xe vs Radeon 780M/890M)?
2. Ubuntu version on each (`lsb_release -a`)?
3. Wired switch available, or Wi-Fi only?
4. Which of the "stretch" games (see T1) do they actually want, given each costs real setup time?
5. Do they have a Steam account per machine, or one account being shared (family sharing / sequential logins)?

---

## 1. Scope

### T1 — Game matrix (decided; do not re-litigate)

| Tier | Game | Runtime | LAN mechanism | Build it? |
|---|---|---|---|---|
| **Core** | Quake 3 Arena | ioquake3, native | Broadcast discovery, fully offline | ✅ Yes |
| **Core** | Counter-Strike: Source | Native Linux + `srcds` | `sv_lan 1`, LAN tab | ✅ Yes |
| **Core** | Left 4 Dead 2 | Native Linux + `srcds` | LAN server + `connect <ip>` | ✅ Yes |
| **Core** | Mario Kart: Double Dash | Dolphin, native | Dolphin NetPlay (GC path) | ✅ Yes |
| Stretch | Mario Kart Wii | Dolphin, native | Dolphin NetPlay (Wii path — experimental) | ⚠️ Only if asked |
| Stretch | Risk of Rain 2 | Proton (no native build) | Dedicated server + console `connect` | ⚠️ Only if asked |
| Stretch | MW2 (2009) | Wine/Proton via IW4x | `sv_lanonly 1` | ⚠️ Only if asked |
| **Excluded** | StarCraft II | Wine works | ❌ LAN removed by design | ❌ No |
| **Excluded** | Quest / PCVR | ALVR + SteamVR-Linux | ❌ No dGPU in any Framework 13 | ❌ No |
| **Excluded** | Fortnite | ❌ EAC blocked by Epic policy | ❌ No LAN mode exists | ❌ No |

**Why the four Core titles:** all native Linux, all genuinely offline-capable after first launch,
all comfortably inside an integrated-GPU frame budget. Combined failure surface is near zero.

### Out of scope

Anything requiring a discrete GPU, anything requiring live matchmaking servers,
and any attempt to defeat anti-cheat. If the user asks for Fortnite or SC2 LAN,
explain the blocker (T1) rather than attempting workarounds.

---

## 2. Repository layout to create

```
lan-party/
├── README.md                  # human-facing quickstart, generated last
├── inventory.yml              # machine list: hostname, ip, iGPU, role
├── bootstrap.sh               # entrypoint: runs phases in order
├── lib/
│   ├── common.sh              # log/die/require_cmd/idempotent helpers
│   └── preflight.sh           # OS, GPU, disk, network checks
├── phases/
│   ├── 10-base.sh             # apt deps, flatpak, ufw
│   ├── 20-quake3.sh
│   ├── 30-source-games.sh     # CS:S + L4D2 shared logic
│   ├── 40-dolphin.sh
│   ├── 50-ror2.sh             # optional
│   └── 60-iw4x.sh             # optional
├── configs/
│   ├── q3/server.cfg
│   ├── srcds/cstrike-server.cfg
│   ├── srcds/l4d2-server.cfg
│   ├── ror2/server.cfg
│   └── iw4x/server.cfg
├── assets/
│   └── .gitkeep               # human drops pak0.pk3, ISOs here; gitignored
├── scripts/
│   ├── host-server.sh <game>  # start a server on this machine
│   ├── join.sh <game> <ip>    # print/execute the join command
│   └── sync-assets.sh <host>  # rsync assets from the staging machine
└── docs/
    ├── runbook.md             # event-day operator sheet
    └── troubleshooting.md
```

`.gitignore` must exclude `assets/`, any `*.pk3`, `*.iso`, `*.rvz`, and anything under
`steamapps/`. **No copyrighted game data in the repo.**

---

## 3. Phases

### Phase 0 — Preflight (`lib/preflight.sh`)

Emit a machine report; fail loudly on anything blocking.

```bash
lsb_release -ds                          # Ubuntu version
lspci | grep -Ei 'vga|3d'                # iGPU identification
glxinfo -B 2>/dev/null | grep -E 'OpenGL renderer|OpenGL version'
vulkaninfo --summary 2>/dev/null | grep -E 'driverName|deviceName'
free -h; df -h /home
ip -4 addr show scope global
ufw status verbose
```

**Acceptance:** report written to `reports/<hostname>-preflight.txt`, and a single-line verdict
(`READY` / `BLOCKED: <reason>`) on stdout.

Note for AMD boards: Mesa RADV is the target driver. If `vulkaninfo` shows llvmpipe,
that's software rendering and the machine is BLOCKED until drivers are fixed.

### Phase 1 — Base (`phases/10-base.sh`)

- `apt` deps: `mesa-utils vulkan-tools mesa-vulkan-drivers rsync curl git ufw`
  plus `libc6:i386 libstdc++6:i386` (32-bit, needed by `srcds` and Wine paths).
  Enable `dpkg --add-architecture i386` first.
- Flatpak + flathub remote (for Dolphin).
- Firewall: **do not blanket-disable ufw.** Add a scoped rule instead.

```bash
LAN_CIDR="192.168.1.0/24"   # detect from ip route, confirm with user
sudo ufw allow from "$LAN_CIDR" comment 'lan-party'
```

**Acceptance:** `ufw status` shows the scoped rule; `dpkg --print-foreign-architectures` shows `i386`.

### Phase 2 — Quake 3 (`phases/20-quake3.sh`)

Highest value, lowest risk. Build this first and prove the whole pipeline on it.

- Install `ioquake3` from apt (GPL-2.0; the de-facto standard Q3 engine and the base for
  most Q3-derived projects).
- Human-supplied step: copy `pak0.pk3` … `pak8.pk3` from a retail/Steam Q3 install into
  `~/.q3a/baseq3/`. Script must **detect and report** missing paks, not guess.
- Fallback if the user has no retail copy: offer **OpenArena** (GPL-2.0, free assets,
  the best-known standalone Q3-engine game) as a drop-in — same engine, same LAN behaviour,
  no license question. Ask before switching.

Server:

```bash
ioq3ded +set dedicated 1 +set sv_hostname "LAN" +set sv_maxclients 16 +map q3dm17
```

**Expected output — this is your success signal:**

```
Opening IP socket: 0.0.0.0:27960
Hostname: LAN
------ Server Initialization ------
```

**Acceptance:** from a second machine, `Multiplayer → Source: Local` lists the server without
any IP being typed. That proves broadcast discovery works and the firewall is right.

### Phase 3 — Source games (`phases/30-source-games.sh`)

CS:S and L4D2 share everything; write one parameterised function.

- Steam is installed and logged in **by the human**. Script verifies, does not automate.
- **The single highest-value prep step in this whole plan:** every laptop must launch each
  game once, online, before the event. Steam offline mode is unreliable otherwise. Script
  should print this as a checklist and record completion in a local state file.
- Optionally install `srcds` via `steamcmd` on the designated server machine
  (CS:S appid 232330, L4D2 appid 222860 — verify these before use).

```bash
# CS:S
srcds_run -game cstrike  +sv_lan 1 +maxplayers 16 +map de_dust2
# L4D2
srcds_run -game left4dead2 +sv_lan 1 +map c1m1_hotel
```

**Expected output:**

```
Connection to Steam servers successful.
   Public IP is 192.168.1.42.
Server is hibernating
```

Client join: `View → Servers → LAN`, or console `connect 192.168.1.42:27015`.

**Acceptance:** two machines connected to one `srcds` instance, `status` on the server console
lists both.

### Phase 4 — Dolphin (`phases/40-dolphin.sh`)

- Install `org.DolphinEmu.dolphin-emu` from Flathub (GPL-2.0+; the dominant GameCube/Wii
  emulator, no serious competitor).
- **Human-supplied:** disc dumps of games they own. The script must not fetch ROMs.
  It creates `~/Games/dolphin/` and reports what's present.
- **Pin identical Dolphin versions across all machines.** NetPlay requires it. Record the
  version in `inventory.yml` and fail the check if machines disagree.
- Configure NetPlay from the official guide: <https://dolphin-emu.org/docs/guides/netplay-guide/>
  - Every player must have the *same* title in their gamelist.
  - Prefer Ethernet: input latency is bounded by connection latency.
  - Target **GameCube** titles (Double Dash). The docs describe GameCube NetPlay as painless
    and Wii NetPlay as temperamental/experimental — that's exactly why MK Wii is a stretch goal.

**Acceptance:** 4-player Double Dash session sustains full speed for one complete Grand Prix
with no desync.

### Phase 5 (optional) — Risk of Rain 2 (`phases/50-ror2.sh`)

Only if the user asked. No native Linux build has ever shipped; it is Proton-only
(<https://www.protondb.com/app/632360>).

- **Pin one Proton version fleet-wide** (Steam → Properties → Compatibility). Behaviour
  differs across builds; drift causes join failures.
- Install *Risk of Rain 2 Dedicated Server* from the Steam **Tools** category on the host.
- `configs/ror2/server.cfg`:

```
sv_port 27015;
sv_maxplayers 4;
sv_hostname "LAN";
steam_server_query_port 27016;
```

- Client join: `Ctrl+Alt+~` to open the console, then `connect "192.168.1.42:27015"`.
  Command reference: <https://riskofrain2.fandom.com/wiki/Developer_Console>
- **Warn the user:** joining is brokered through Steamworks, so this one is not truly offline,
  and frame cost scales with projectile count — late runs will drop frames on an iGPU.

### Phase 6 (optional) — MW2 2009 via IW4x (`phases/60-iw4x.sh`)

Only if the user asked, and only for **MW2 (2009)**. MW2 (2022) is a hard no — kernel anti-cheat.

- Requires a **Steam** installation of MW2; Microsoft Store copies are explicitly incompatible
  (<https://github.com/iw4x/iw4x-client>). Note the repo's license is a custom
  academic-research clause, not an OSI license — do not redistribute.
- Client runs under Wine/Proton. Server under Wine on one machine:

```bash
wine iw4x.exe -dedicated -stdout \
  +set sv_lanonly 1 +set net_port 28960 \
  +set sv_maxclients 12 +exec server.cfg +map_rotate
```

`-stdout` is documented as the flag for running the server under Wine; `sv_lanonly 1` makes it
LAN-only (<https://github.com/Emosewaj/IW4x/wiki/Advanced-general-server-configuration>).
A containerised Wine server image also exists (<https://github.com/andrebossi/iw4x-docker>, MIT)
if the user prefers to isolate it.

**Acceptance:** two clients in one LAN match, internet cable physically unplugged.

---

## 4. Asset staging

One machine is the **staging host**. Everything flows from it.

```bash
# scripts/sync-assets.sh
rsync -avh --progress --partial \
  "${STAGING_HOST}:~/lan-party/assets/" ~/lan-party/assets/
```

Do not use USB sticks for multi-gigabyte transfers across 12 machines — the switch is
an order of magnitude faster and parallel.

---

## 5. Risk register — build mitigations, not hope

| Risk | Mitigation to implement |
|---|---|
| Steam offline mode fails | Pre-event online launch of every game on every machine, tracked in a state file |
| Wi-Fi saturation with N clients | Gigabit switch; Ethernet expansion cards / USB-C dongles for competitive titles |
| ufw blocks LAN discovery | Scoped `ufw allow from <LAN_CIDR>` (Phase 1), never a blanket disable |
| Dolphin version mismatch | Version pinned and asserted in `inventory.yml` |
| Proton version drift (RoR2) | Pinned per-game compatibility tool, verified by script |
| Missing game assets discovered day-of | Preflight reports missing assets by exact filename, days early |
| Software rendering (llvmpipe) | Preflight hard-fails the machine |

---

## 6. Deliverables and definition of done

- [ ] `bootstrap.sh` runs clean and idempotently on a fresh Ubuntu Framework 13
- [ ] Preflight report generated for every machine in `inventory.yml`
- [ ] All four Core games launch and complete a 2-machine LAN match
- [ ] **Uplink-unplug test:** Q3 and Dolphin sessions survive the internet cable being pulled
- [ ] `docs/runbook.md` written for a non-technical operator: one page, per game — how to host,
      how to join, what the success output looks like, what to do when it doesn't appear
- [ ] `docs/troubleshooting.md` covers: server invisible in LAN tab, Steam offline failure,
      Dolphin desync, Proton launch failure
- [ ] `README.md` quickstart, written last, from what was actually built

---

## 7. Suggested build order

1. Phase 0 + 1 on one machine. Get preflight honest before automating anything.
2. Phase 2 (Quake 3) end-to-end on two machines. **This proves network, firewall, and discovery.**
   Everything downstream inherits that proof.
3. Phase 3 (Source games) — the biggest player-experience win.
4. Phase 4 (Dolphin) — the most likely to need per-machine tuning.
5. Phases 5/6 only after 2–4 are green and only if requested.
6. Docs and runbook last, describing reality rather than intent.

---

## Appendix — Sources

Verified during research:

- Fortnite / Linux: <https://www.pcgamer.com/tim-sweeney-says-epic-wont-support-fortnite-on-steam-deck/>,
  <https://www.gamingonlinux.com/2025/03/as-epic-games-continue-ignoring-linux-steam-deck-for-fortnite-theyre-putting-it-on-windows-arm/>
- SC2 LAN removal: <https://en.wikipedia.org/wiki/StarCraft_II:_Wings_of_Liberty>
- Dolphin NetPlay: <https://dolphin-emu.org/docs/guides/netplay-guide/>
- RoR2 Proton status: <https://www.protondb.com/app/632360>
- RoR2 console/dedicated server: <https://riskofrain2.fandom.com/wiki/Developer_Console>,
  <https://steamcommunity.com/sharedfiles/filedetails/?id=1938378081>
- IW4x client: <https://github.com/iw4x/iw4x-client>
- IW4x server flags: <https://github.com/Emosewaj/IW4x/wiki/Advanced-general-server-configuration>
- IW4x Docker (MIT): <https://github.com/andrebossi/iw4x-docker>
- ALVR requirements (why PCVR is excluded): <https://github.com/alvr-org/ALVR>

Canonical URLs referenced but not fetched during research — **the agent should confirm these
resolve before relying on them:** `ioquake3.org`, `github.com/ioquake/ioq3`, `openarena.ws`,
`developer.valvesoftware.com`, and Steam appids for `srcds` installs.
