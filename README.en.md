# Claude Auth Switcher

[繁體中文](README.md) · **English** · [日本語](README.ja.md)

Manage multiple Claude Code subscription accounts on one machine.
Switch the active account instantly without logging out and back in. Works on **Windows**, **Linux**, and **macOS**.

**[Full guide → yazelin.github.io/claude-auth-switcher](https://yazelin.github.io/claude-auth-switcher/en/)**

Sibling project to [codex-auth-switcher](https://github.com/yazelin/codex-auth-switcher) — same idea, for Claude Code.

## Quick Install

**Windows PowerShell** — open any PowerShell window and paste:

```powershell
irm https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.ps1 | iex
```

No extra dependencies (uses built-in `ConvertFrom-Json` / `Invoke-RestMethod`).

**Linux / macOS** — open any bash or zsh terminal and paste:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.sh)
```

Requires `git`, `jq`, and `curl`.

Both installers clone the repo, wire `cl` into your shell profile, and print a first-time setup guide. Open a new shell afterward.

## Why

If you have, say, a personal Claude account and a company one (each with its own
subscription and its own usage limits), this lets you flip between them with one
command instead of re-authenticating every time.

## How it works

Claude Code keeps your account identity in **two** files, and `cl` switches both:

- `~/.claude/.credentials.json` → the `claudeAiOauth` block (your **account token**)
- `~/.claude.json` → the `oauthAccount` block (your **subscription identity**)

If only the token is swapped, Claude Code sees a mismatch and silently falls back
to **API billing**. `cl use` rewrites both blocks together, so switching keeps you
on your Pro / Max subscription. Expired tokens are refreshed automatically on switch.

Everything else is left untouched and shared across accounts:

| Item | Location | Switched / Shared |
|---|---|---|
| `claudeAiOauth` (account token) | `~/.claude/.credentials.json` | **switched per profile** |
| `oauthAccount` (subscription identity) | `~/.claude.json` | **switched per profile** |
| `mcpOAuth` (MCP server tokens) | `~/.claude/.credentials.json` | shared |
| settings, history, skills, plugins | `~/.claude/` | shared |

One account is active at a time (switching rewrites the active token in place).

## First-time setup

```bash
# While logged into account #1 in Claude Code:
cl import personal

# Add account #2 via browser OAuth (or log in with Claude Code, then `cl import`):
cl login company

# From now on:
cl use company      # switch active account (kills running claude first)
cl switch           # interactive switcher
cl list             # see profiles, active marker, cached usage
cl usage --all      # live usage % for every account
```

After switching, just run `claude` as usual — there is no wrapper command to remember.

## Commands

```
cl login <name>        Add a new account (opens browser OAuth)
cl import <name>       Save current ~/.claude account as a profile
cl use <name>          Switch active account (kills running claude first)
cl switch              Interactive switcher (kills running claude first)
cl kill                Kill all running claude processes
cl list                Table of profiles: active marker, email, plan, cached usage
cl usage [name|--all]  Live usage table for all accounts; name = one account's detail
cl current             Print active profile
cl remove <name>       Delete a profile
cl ps                  List running claude processes (excludes this session)
cl doctor              Show paths, claude process state, profile summary
cl export <archive>    Back up all profiles (Windows .zip / Linux .tgz)
cl restore <archive>   Restore profiles from archive
cl help                Show this help
```

`cl use` accepts `--force` (switch even if the current account isn't saved yet) and
`--no-kill` (don't kill running `claude` first; or set `CL_NO_KILL=1`).

### Switching in detail

`cl switch` lists your profiles and prompts for a number:

```
select a profile:
  1) personal
  2) company
choice: 2
killed 1 running claude process(es) before switching
switched to 'company'
```

A **running `claude` session writes its cached token back** on its next API call,
which would silently undo a switch. So `cl use` and `cl switch` kill live `claude`
processes before swapping the credential files. The process that launched `cl` (and
its ancestors) is never killed, so running `cl` from inside a Claude session won't
terminate that session mid-switch.

## Usage

`cl list` prints an aligned table — one row per account — using each profile's
cached usage:

```
CURRENT  PROFILE      EMAIL                  PLAN   USAGE
*        personal     ya***@gmail.com        max    5h 42% used @14:00 | wk 18% used @06/02
         company      ya***@company.com      pro    5h 7% used @09:00 | wk 55% used @06/05
```

Plain `cl list` does not hit the network. `cl usage` (with no argument, or `--all`)
refreshes every account's usage live and then prints the same table, so you can
compare accounts side by side. `cl usage <name>` fetches just that account and shows
the per-bucket detail:

```
personal:
5h               42% used   reset 05/29 14:00
weekly           18% used   reset 06/02 09:00
weekly-opus       3% used   reset 06/02 09:00
weekly-sonnet    27% used   reset 06/02 09:00
```

Percentages are **used**, not remaining (the opposite of codex-auth-switcher, which
shows remaining). Emails are masked for display.

## Environment

- `CL_PROFILES_DIR` — profile store (default `~/.claude_auth_profiles`)
- `CL_CRED` — credentials file (default `~/.claude/.credentials.json`)
- `CL_ACCOUNT` — account-identity file (default `~/.claude.json`, holds `oauthAccount`)
- `CL_NO_KILL=1` — don't kill running `claude` before switching

## Safety

- Switching refuses to overwrite the current account if it isn't saved as a
  profile yet (use `--force` to override). This stops you from accidentally losing
  an unsaved login.
- Profile files contain long-lived refresh tokens — on Unix the profile directory is
  created `chmod 700` and files `chmod 600`. `.gitignore` keeps profiles and
  exported archives out of version control.
- On Windows, `cl` writes `.credentials.json` as **UTF-8 without a BOM**. A BOM makes
  Claude Code's Node-based reader treat the session as logged out, so this is handled
  automatically — don't hand-edit the file with an editor that adds one.
- Switching while a `claude` process is running will change that session's token on
  its next API call, so `cl use` / `cl switch` kill live `claude` first.

## Windows

`bin/cl.ps1` mirrors the same commands and profile layout in PowerShell (no `jq`
dependency — uses built-in `ConvertFrom-Json`). Verified on Windows 11 with
Windows PowerShell 5.1 — `cl import` / `cl use` / `cl switch` all work.

`install-oneliner.ps1` clones the repo to `%USERPROFILE%\claude-auth-switcher`
(override with `$env:CL_DEST` / `$env:CL_REPO`), then `install.ps1` wires `cl`
into both your Windows PowerShell 5.1 and PowerShell 7 profiles, so it works
whichever host you launch.

See `docs/superpowers/specs/2026-05-29-claude-auth-switcher-design.md` for design
details.

## Uninstall

Removes the shell wiring (the `cl` command). Your saved accounts are kept by default.

**Linux / macOS**

```bash
bash ~/claude-auth-switcher/uninstall.sh
# also delete saved accounts:
bash ~/claude-auth-switcher/uninstall.sh --purge
```

**Windows PowerShell**

```powershell
& "$HOME\claude-auth-switcher\uninstall.ps1"
# also delete saved accounts:
& "$HOME\claude-auth-switcher\uninstall.ps1" -Purge
```

The uninstaller strips the `# claude-auth-switcher` block and its `source` line
from your shell profile (a `.cl-bak` backup is written first), but **keeps** the
repo itself and the saved accounts in `~/.claude_auth_profiles`. It prints the
command to delete the repo manually when it finishes; pass `--purge` / `-Purge`
to also delete saved accounts.

## License

MIT — see [LICENSE](LICENSE).
