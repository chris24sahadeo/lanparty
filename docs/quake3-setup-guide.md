# The source guide, and what of it applies to Ubuntu

The Quake III setup this repo automates started from a personal Notion page headed
"macOS Apple Silicon / ubuntu". That page is not public and not durable, so its substance
is preserved here -- otherwise the repo encodes a set of decisions whose reasoning lives
somewhere nobody else can read.

The page has two halves. The engine half is delivery-specific. The config half is
engine-level and applies unchanged to Linux.

## Part 1 -- installing the engine (macOS instructions, substituted on Ubuntu)

The guide, following <https://www.applegamingwiki.com/wiki/Quake_3_Arena>:

1. Download `ioquake3-1.36.dmg` from <https://github.com/MacSourcePorts/ioq3/releases>.
2. Open the dmg and copy the app into `/Applications`.
3. Copy the contents of the original Quake III Arena `baseq3` folder to
   `~/Library/Application Support/Quake3/baseq3`.

Attachments: `baseq3.zip`, `q3config.cfg`.

### What we do instead

MacSourcePorts ships a Mac build of the *same* upstream ioquake3 1.36 that Ubuntu
packages, so only the delivery changes:

| Guide (macOS) | Ubuntu 24.04 |
| --- | --- |
| `ioquake3-1.36.dmg` from MacSourcePorts | `apt install ioquake3 ioquake3-server` (noble/universe) |
| `/Applications/ioquake3.app` | `/usr/lib/ioquake3/ioquake3`, `/usr/lib/ioquake3/ioq3ded` |
| `~/Library/Application Support/Quake3/baseq3` | `/usr/lib/quake3/base/baseq3` (system), `~/.q3a/baseq3` (per user) |
| `baseq3.zip` | the same file, unpacked by `roles/quake3_common` |
| `q3config.cfg` | the same file, installed as `autoexec.cfg` -- see below |

## Part 2 -- configuration (applies to Ubuntu as written)

Source: <https://steamcommunity.com/sharedfiles/filedetails/?id=1901101681>

### Resolution

Quake III predates widescreen. Set fullscreen with `r_fullscreen 1`, then `r_mode -1` to
tell the engine to use `r_customwidth` / `r_customheight`, set those to your panel's
resolution, and `vid_restart` to apply.

> This repo detects the resolution per machine instead of hardcoding it. See
> `docs/quake3-reference.md`.

### Field of view

`cg_fov x`, default 90. Most players use 100-120. Adjust it during a match until it feels
right.

### Mouse

- `in_mouse 1` for raw input, `-1` for the legacy win32 path.
  **`-1` is Windows-only and meaningless on Linux; this repo pins `1`.**
- `sensitivity x` -- default 5.
- `cl_mouseAccel x` -- most players use 0. If your mouse accelerates oddly on fast flicks
  (rocket jumps, corner flicks), a small negative value helps; `-0.015` works well.
  Going much further makes the cursor drift opposite your hand.
- `m_yaw x` / `m_pitch x` -- post-acceleration horizontal and vertical multipliers.
  Default 0.022. Pointless to change unless `cl_mouseAccel` is non-zero; 0.008 to 0.015
  if it is.
- Using different `m_pitch` and `m_yaw` per aspect ratio is sometimes suggested. It wrecks
  muscle memory. Don't.

### Frames per second

- `cg_drawFPS 1` shows the counter.
- `com_maxfps x` -- 125, 250, or higher.
- `r_swapinterval 0` -- vsync off.
- FPS is capped at 125 online. *(This is a server `sv_fps` interaction; on our own LAN
  server we set `sv_fps 40` and still use 125 client-side, because Quake III's jump
  physics are framerate-coupled and 125 is the canonical value.)*
- Setting FPS above your monitor's refresh rate is still worth doing.
- If FPS is low anyway: `r_displayRefresh 0` to auto-pick the refresh rate, and
  `r_primitives 2` has helped some people. *(The guide also suggests disabling threaded
  optimisation in the Nvidia control panel -- Windows-only, dropped.)*

### Misc

- `cg_trueLightning 1` -- the lightning gun beam tracks the crosshair instead of lagging
  behind it when you turn.
- `cg_oldRail 0` -- rail beam with coloured rings. `color1` / `color2`, integers 1-8.
- `cg_oldRocket 0` -- new rocket model.

## The one place this repo deliberately disobeys the guide

The guide says to install `q3config.cfg`. **We install the identical content as
`autoexec.cfg`.**

The engine rewrites `q3config.cfg` from its live cvar state on every clean exit. Install a
tuned config under that name and the first player to quit silently replaces it with
whatever the menus happened to contain -- permanently, on that machine. You can watch it
happen: compare the mtimes of `autoexec.cfg` and `q3config.cfg` after one session.

`autoexec.cfg` is exec'd *after* `q3config.cfg` on every start, so it wins each launch and
survives the writeback. Same content, correct filename.
