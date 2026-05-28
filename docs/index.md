# Claude Auth Switcher

Manage multiple Claude Code subscription accounts on one machine — switch the
active account instantly without logging out and back in.

Have a personal Claude account and a company one, each with its own subscription
and usage limits? Flip between them with one command.

## Install (Linux / macOS-shell)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.sh)
```

Requires `jq` and `curl`. Open a new shell afterward.

## Use

```bash
cl import personal     # save the account you're logged into now
cl import company      # log into the other account first, then import
cl use company         # switch
cl list                # profiles + active marker + cached usage
cl usage --all         # live 5-hour and weekly usage % per account
```

## How it works

Switching swaps only the `claudeAiOauth` block of `~/.claude/.credentials.json`,
leaving your MCP tokens, settings, history, skills, and plugins shared across
accounts. Expired tokens are refreshed automatically.

Full command reference and source: [github.com/yazelin/claude-auth-switcher](https://github.com/yazelin/claude-auth-switcher).
