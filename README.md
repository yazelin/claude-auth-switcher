# Claude Auth Switcher

Manage multiple Claude Code subscription accounts on one machine.
Switch the active account instantly without logging out and back in. Linux and Windows.

Sibling project to [codex-auth-switcher](https://github.com/yazelin/codex-auth-switcher) — same idea, for Claude Code.

## Why

If you have, say, a personal Claude account and a company one (each with its own
subscription and its own usage limits), this lets you flip between them with one
command instead of re-authenticating every time.

## How it works

Claude Code keeps your login in `~/.claude/.credentials.json`. That file mixes two
unrelated things:

- `claudeAiOauth` — your **account** token (this is what differs per account)
- `mcpOAuth` — OAuth tokens for your **MCP servers** (account-independent)

`cl` saves each account's `claudeAiOauth` block as a named profile, and switching
**only** swaps that block back in — your MCP tokens, settings, history, skills and
plugins are left untouched and shared across accounts. Expired tokens are refreshed
automatically on switch.

One account is active at a time (switching rewrites the active token in place).

## Install

**Linux / macOS-shell** — paste into a terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.sh)
```

Requires `jq` and `curl`. Open a new shell afterward.

**Windows** — see [Windows notes](#windows) below (verification pending).

## First-time setup

```bash
# While logged into account #1 in Claude Code:
cl import personal

# Log into account #2 in Claude Code (claude /login), then:
cl import company

# From now on:
cl use company      # switch active account
cl list             # see profiles, active marker, cached usage
cl usage --all      # live usage % for every account
```

## Commands

```
cl import <name>       Save current ~/.claude account as a profile
cl use <name>          Switch active account (merges only claudeAiOauth)
cl switch              Interactive switcher
cl list                List profiles, active marker, cached usage
cl usage [name|--all]  Fetch live usage (5-hour and weekly %); default: active
cl current             Print active profile
cl remove <name>       Delete a profile
cl export <a.tgz>      Back up all profiles
cl restore <a.tgz>     Restore profiles from archive
cl doctor              Show paths, claude process state, profile summary
cl help                Show this help
```

Environment:

- `CL_PROFILES_DIR` — profile store (default `~/.claude_auth_profiles`)
- `CL_CRED` — credentials file (default `~/.claude/.credentials.json`)

## Safety

- Switching refuses to overwrite the current account if it isn't saved as a
  profile yet (use `--force` to override). This stops you from accidentally losing
  an unsaved login.
- Profile files contain long-lived refresh tokens — the profile directory is
  created `chmod 700` and files `chmod 600`. `.gitignore` keeps profiles and
  exported archives out of version control.
- Switching while a `claude` process is running will change that session's token
  on its next API call; `cl switch` warns you when it detects one.

## Windows

`bin/cl.ps1` mirrors the same commands and profile layout in PowerShell (no `jq`
dependency — uses built-in `ConvertFrom-Json`). The exact credential read/write
path on Windows is pending verification on a real Windows machine; see
`docs/superpowers/specs/2026-05-29-claude-auth-switcher-design.md` section 4.

## License

MIT — see [LICENSE](LICENSE).
