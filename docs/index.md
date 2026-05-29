---
layout: default
title: Claude Auth Switcher
---

# Claude Auth Switcher

Manage multiple Claude Code subscription accounts on one machine.
Switch the active account instantly without logging out and back in. Works on **Windows**, **Linux**, and **macOS**.

Have a personal Claude account and a company one, each with its own subscription
and usage limits? Flip between them with one command.

---

## Install

### Windows PowerShell — one line

Open any PowerShell window and paste:

```powershell
irm https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.ps1 | iex
```

No extra dependencies. The installer clones the repo to `%USERPROFILE%\claude-auth-switcher`,
wires `cl` into both your Windows PowerShell 5.1 and PowerShell 7 profiles, and prints
the next-steps guide. Open a new PowerShell afterward.

### Linux / macOS — one line

Open any bash or zsh terminal and paste:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.sh)
```

Requires `git`, `jq`, and `curl`. Open a new shell afterward.

---

## First-Time Setup

```bash
# Save the account you're logged into now as a profile named "personal"
cl import personal

# Add a second account via browser OAuth
cl login company

# Check what was saved
cl list
```

**Output example:**

```
CURRENT  PROFILE      EMAIL                  PLAN   USAGE
*        personal     ya***@gmail.com        max    5h 42% used @14:00 | wk 18% used
         company      ya***@company.com      pro    5h 7% used         | wk 55% used
```

`*` marks the active account; emails are masked. Percentages are **used** (5-hour / weekly).

---

## Daily Commands

### Switch accounts

```bash
cl switch          # interactive picker — kills running claude first
cl use company     # or switch directly to a named profile
```

After switching, just run `claude` as usual — there is no wrapper command.

```
select a profile:
  1) personal
  2) company
choice: 2
killed 1 running claude process(es) before switching
switched to 'company'
```

### All commands

| Command | What it does |
|---|---|
| `cl login <name>` | Add a new account (opens browser OAuth) |
| `cl import <name>` | Save the current `~/.claude` account as a profile |
| `cl use <name>` | Switch the active account (kills running claude first) |
| `cl switch` | Interactive switcher — kills running claude first |
| `cl kill` | Kill all running claude processes |
| `cl list` | Table of profiles: active marker, email, plan, cached usage |
| `cl usage [name\|--all]` | Live usage; `--all` refreshes all + shows the table; a name shows per-bucket detail |
| `cl current` | Print the active profile name |
| `cl remove <name>` | Delete a saved profile |
| `cl ps` | Show detected claude processes (excludes this session) |
| `cl doctor` | Diagnostics — paths, process state, profile summary |
| `cl export <archive>` | Back up all profiles (Windows `.zip` / Linux `.tgz`) |
| `cl restore <archive>` | Restore profiles from an archive |
| `cl help` | Show built-in command reference |

---

## How It Works

Claude Code keeps your account identity in **two** files, and `cl` switches both:

| Item | Location | Switched / Shared |
|---|---|---|
| `claudeAiOauth` (account token) | `~/.claude/.credentials.json` | switched per profile |
| `oauthAccount` (subscription identity) | `~/.claude.json` | switched per profile |
| `mcpOAuth` (MCP server tokens) | `~/.claude/.credentials.json` | shared |
| settings, history, skills, plugins | `~/.claude/` | shared |

If only the token is swapped, Claude Code sees a mismatch and silently falls back to
**API billing**. `cl` rewrites both blocks together, so switching keeps you on your
Pro / Max subscription. Expired tokens are refreshed automatically on switch.

A running `claude` session writes its cached token back on its next API call, which
would undo a switch — so `cl use` and `cl switch` kill live `claude` processes first.

---

## Usage Tracking

`cl list` shows each account's cached usage in one aligned table (see above).
`cl usage --all` refreshes every account live and reprints that table so you can
compare them side by side. `cl usage <name>` fetches one account and shows the
per-bucket detail:

```
personal:
5h               42% used   reset 05/29 14:00
weekly           18% used   reset 06/02 09:00
weekly-opus       3% used   reset 06/02 09:00
weekly-sonnet    27% used   reset 06/02 09:00
```

Percentages are **used**, not remaining. Plain `cl list` does not hit the network.

---

## Security Notes

Profiles contain long-lived refresh tokens. Do **not** commit `~/.claude_auth_profiles`
or any exported archive — both contain tokens. On Unix the profile directory is created
`chmod 700` and files `chmod 600`.

On Windows, `cl` writes `.credentials.json` as UTF-8 without a BOM (a BOM makes Claude
Code treat the session as logged out).

---

## Source

[github.com/yazelin/claude-auth-switcher](https://github.com/yazelin/claude-auth-switcher)
