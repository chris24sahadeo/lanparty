# Working in this repo

Ansible for a LAN party. Read `README.md` first -- it covers what the repo does and why
the game deliberately avoids the tailnet. This file is the rules for changing it.

## The one thing that must not break

**This is layer 3.** Two other Ansible trees run on the same workstation:

| | tree | roles |
| --- | --- | --- |
| layer 1 | a work provisioning repo | 13 |
| layer 2 | a personal workstation repo | 34 |

They share `~/.ansible/collections` (`community.general 13.3.0`, `ansible.posix 2.2.2`)
and `~/.local/bin/ansible*` (a uv shim on `ansible-core 2.21.2`). A bare
`ansible-galaxy collection install`, or a `uv tool install --force ansible-core` at a
different version, silently breaks both of them.

Four mechanisms stop that, all of them load-bearing. The reasoning is in the header of
`ansible.cfg`; do not weaken any of them:

1. `bootstrap.sh` exports `ANSIBLE_CONFIG` to this repo's absolute cfg path.
2. `collections_path = .collections`, in-tree and gitignored.
3. `local_tmp = .ansible-tmp` -- galaxy stages tarballs in `~/.ansible/tmp` otherwise.
4. `ansible-core` in `.venv`, stock `python3 -m venv`. Never a global install.

Never create `~/.ansible.cfg` or `/etc/ansible/` -- neither exists today, and either would
apply to all three trees.

`test/container.sh` proves it: full playbook in a throwaway container, then `~/.ansible`
must be byte-identical.

## One owner per thing

Do not add anything here that layer 1 or layer 2 already installs: Tailscale,
`openssh-server` / `authorized_keys`, Docker, Homebrew, anything in `~/.local/bin`, MIME
associations, `.desktop` defaults, `~/.claude`, chezmoi-managed dotfiles. Two owners means
two copies resolved only by PATH order, or two roles reporting `changed` forever.

Add no apt source and no PPA. Everything needed is in stock Ubuntu universe.

This repo owns: `/usr/lib/quake3/base/baseq3/`, `/var/games/quake3-server/`,
`/etc/systemd/system/lanparty-*.service`, `/usr/local/bin/lanparty-*`, `~/.q3a/`, and one
marker-scoped block in `/etc/hosts`.

## Firewall

Open ports on a firewall that is already active. **Never enable one.** Turning on ufw from
a game playbook is a real way to break someone's workstation, especially a Docker host
where ufw does not filter Docker's iptables chain. `roles/game_host` probes and acts
accordingly.

## Conventions

- Roles are `roles/<snake_case>/tasks/main.yml`, plus `files/` and `handlers/` where
  needed. No `defaults/`, no `meta/`.
- Every variable is prefixed `lanparty_` and lives in `group_vars/all.yml`. One file, so a
  grep for the prefix finds every knob.
- Play-level `become: false`; individual tasks opt in with `become: true`. Keeps the sudo
  surface small and visible, and a `--tags preflight` run never prompts.
- One tag per role in `site.yml`, matching the role's purpose.
- **Idempotent, always.** A second run reports `changed=0`. Guard with `stat` / `creates` /
  state checks and actually verify the second run before calling something done.
- Probe tasks carry `changed_when: false` and, where a non-zero exit is information rather
  than failure, `failed_when: false`.
- Inline `copy: content:` with Jinja rather than `.j2` templates. Same result, and the
  content stays next to the comment explaining it.
- ASCII only. `->` not an arrow, `deg` not a degree sign, `--` not an em dash.
- **Expand every acronym on first use**, in comments as much as in prose: `MTU (Maximum
  Transmission Unit)`, `NIC (Network Interface Card)`, `CGNAT (Carrier Grade Network
  Address Translation)`.
- Comments say **why X and not Y**, especially where a plausible alternative was rejected.
  A path that looks arbitrary and is not needs a sentence saying so.

## Game data never enters git

**This has been asked and the answer is settled.** `pak0.pk3` is retail id Software data
and is not licensed for redistribution -- Debian ships `game-data-packager`, a tool that
builds a package from the user's own copy, precisely so it never has to host the copy.
This repo is public, so committing it would be republishing commercial content under the
owner's name. It also cannot work mechanically: GitHub rejects any file over 100 MB, the
archive is ~637 MB, and Git LFS's free tier is 1 GB of storage and 1 GB of bandwidth a
month -- about one clone.

The goal behind the request -- nobody typing a path -- is met instead by
`roles/quake3_common/files/find-game-data.sh`, which searches the places the data really
lives and uses the first hit. If someone wants the data version-controlled, a PRIVATE
repo or a release asset on one is the route; do not move it here.

## Shell logic goes in files/, not inline

`roles/quake3_common/files/find-game-data.sh` is a script rather than an inline `shell:`
task for a concrete reason: Ansible runs `split_args()` over a free-form shell blob
looking for `chdir=` and friends, and that parse dies on an unbalanced quote -- including
an apostrophe inside a comment. The error it gives ("failed at splitting arguments, either
an unbalanced jinja2 block or quotes") points at the task, not the apostrophe. A file has
no such hazard, and shellcheck can read it.

### Details

The repo is public. `pak0.pk3` is retail id Software data. `.gitignore` blocks `*.pk3`,
`baseq3.zip` and `baseq3/`; keep it that way. Passwords too -- `lanparty_quake3_rcon_password`
ships as `changeme` and a real one is passed with `-e` or vaulted.

## Where the knowledge lives

`docs/quake3-setup-guide.md` preserves the personal Notion page this setup came from,
plus a part-by-part note on what of it applies to Linux. `docs/quake3-reference.md` is the
engine reference -- paths, AppArmor rules, which cvars are command-line-only, how the LAN
browser works and why an overlay network breaks it, client tuning defaults and clamps.

Check `docs/quake3-reference.md` before changing a cvar or a path. Most of what looks
arbitrary in the roles is load-bearing and the reason is written down there.

## The config file chain

Three files, read in order, later ones winning: `q3config.cfg` (written by the ENGINE on
every quit), `autoexec.cfg` (Ansible, overwritten every run), `lanparty-local.cfg`
(created once with `force: false`, then the player's).

Two rules follow from that. **Never install a config as `q3config.cfg`** -- the engine
overwrites it the first time anyone quits. And **never make Ansible rewrite
`lanparty-local.cfg`**; `force: false` is the only reason a person has anywhere to put a
setting and find it again.

## Adding a game

Write `games/<id>.yml` against the contract documented in `games/quake3.yml`, write the
roles it names, set `lanparty_game`. `site.yml` must keep working without naming any
game -- if a change makes it mention Quake, the abstraction is in the wrong place.

## Git

Branch `chris/<topic>`. Never commit directly to `master`.
