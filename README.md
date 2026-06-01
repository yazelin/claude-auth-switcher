# Claude Auth Switcher

**繁體中文** · [English](README.en.md) · [日本語](README.ja.md)

在一台電腦上管理多個 Claude Code 訂閱帳號。
即時切換使用中的帳號，不需登出再重新登入。支援 **Windows**、**Linux** 與 **macOS**。

**[完整說明 → yazelin.github.io/claude-auth-switcher](https://yazelin.github.io/claude-auth-switcher/)**

姊妹專案 [codex-auth-switcher](https://github.com/yazelin/codex-auth-switcher) — 同樣的概念，給 Claude Code 用。

## 快速安裝

**Windows PowerShell** — 開啟任一 PowerShell 視窗並貼上：

```powershell
irm https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.ps1 | iex
```

不需額外相依套件（使用內建的 `ConvertFrom-Json` / `Invoke-RestMethod`）。

**Linux / macOS** — 開啟任一 bash 或 zsh 終端機並貼上：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.sh)
```

需要 `git`、`jq` 與 `curl`。

兩種安裝程式都會 clone 此 repo、把 `cl` 接進你的 shell profile，並印出第一次設定的指南。裝完請重開一個 shell。

## 為什麼需要它

如果你有，比方說，一個個人 Claude 帳號和一個公司帳號（各自有獨立的訂閱與用量上限），這個工具讓你用一個指令在它們之間切換，而不必每次都重新驗證登入。

## 運作原理

Claude Code 把你的帳號身分存在**兩個**檔案裡，`cl` 會同時切換這兩個：

- `~/.claude/.credentials.json` → `claudeAiOauth` 區塊（你的**帳號權杖**）
- `~/.claude.json` → `oauthAccount` 區塊（你的**訂閱身分**）

如果只換掉權杖，Claude Code 會偵測到不一致，並悄悄退回成 **API 計費**。`cl use` 會把這兩塊一起改好，所以切換後仍然走你的 Pro / Max 訂閱。過期的權杖也會在切換時自動更新。

其他所有東西都維持原狀、在各帳號間共用：

| 項目 | 位置 | 切換 / 共用 |
|---|---|---|
| `claudeAiOauth`（帳號權杖） | `~/.claude/.credentials.json` | **每個帳號切換** |
| `oauthAccount`（訂閱身分） | `~/.claude.json` | **每個帳號切換** |
| `mcpOAuth`（MCP server token） | `~/.claude/.credentials.json` | 共用 |
| 設定、歷史、技能、外掛 | `~/.claude/` | 共用 |

同一時間只有一個帳號是使用中的（切換會就地改寫使用中的權杖）。

## 第一次設定

```bash
# 在 Claude Code 已登入帳號 #1 的狀態下：
cl import personal

# 透過瀏覽器 OAuth 新增帳號 #2（或先用 Claude Code 登入，再 `cl import`）：
cl login company

# 從此以後：
cl use company      # 切換使用中帳號（會先關掉正在跑的 claude）
cl switch           # 互動式選單切換
cl list             # 查看 profile、使用中標記、快取用量
cl usage --all      # 每個帳號的即時用量 %
```

切換後，照常執行 `claude` 即可 — 沒有需要記住的 wrapper 指令。

## 指令

```
cl login <name>        新增帳號（開啟瀏覽器 OAuth）
cl import <name>       把目前 ~/.claude 帳號存成 profile
cl use <name>          切換使用中帳號（會先關掉正在跑的 claude）
cl switch              互動式切換選單（會先關掉正在跑的 claude）
cl kill                關閉所有正在跑的 claude 程序
cl list                表格列出 profile：使用中標記、email、訂閱、快取用量
cl usage [name|--all]  全部帳號的即時用量表；給名稱則顯示該帳號的分項
cl current             印出使用中的 profile
cl remove <name>       刪除一個 profile
cl ps                  列出正在跑的 claude 程序（排除本 session）
cl doctor              顯示路徑、claude 程序狀態、profile 概覽
cl export <archive>    備份所有 profile（Windows .zip / Linux .tgz）
cl restore <archive>   從備份檔還原 profile
cl help                顯示此說明
```

`cl use` 接受 `--force`（即使目前帳號還沒存成 profile 也照樣切換）與
`--no-kill`（切換前不關掉正在跑的 `claude`；或設定 `CL_NO_KILL=1`）。

### 切換細節

`cl switch` 會列出你的 profile 並提示輸入編號：

```
select a profile:
  1) personal
  2) company
choice: 2
killed 1 running claude process(es) before switching
switched to 'company'
```

**正在跑的 `claude` session 會在下一次呼叫 API 時把自己的快取權杖寫回去**，這會悄悄蓋掉切換結果。所以 `cl use` 和 `cl switch` 會在改寫憑證檔之前先關掉正在跑的 `claude` 程序。啟動 `cl` 的那個程序（以及它的上層程序）永遠不會被關掉，所以在 Claude session 內執行 `cl` 不會在切換途中終止那個 session。

## 用量

`cl list` 會印出一個對齊的表格 — 每個帳號一列 — 使用每個 profile 的快取用量：

```
CURRENT  PROFILE      EMAIL                  PLAN   USAGE
*        personal     ya***@gmail.com        max    5h 42% used @14:00 | wk 18% used @06/02
         company      ya***@company.com      pro    5h 7% used @09:00 | wk 55% used @06/05
```

單純的 `cl list` 不會連網。`cl usage`（不帶參數，或 `--all`）會即時更新每個帳號的用量，再印出同樣的表格，讓你並排比較各帳號。`cl usage <name>` 只抓取那個帳號並顯示每個分項的細節：

```
personal:
5h               42% used   reset 05/29 14:00
weekly           18% used   reset 06/02 09:00
weekly-opus       3% used   reset 06/02 09:00
weekly-sonnet    27% used   reset 06/02 09:00
```

百分比是**已用量**，不是剩餘量（和 codex-auth-switcher 相反，那邊顯示的是剩餘）。email 顯示時會遮罩。

## 環境變數

- `CL_PROFILES_DIR` — profile 儲存位置（預設 `~/.claude_auth_profiles`）
- `CL_CRED` — 憑證檔（預設 `~/.claude/.credentials.json`）
- `CL_ACCOUNT` — 帳號身分檔（預設 `~/.claude.json`，存放 `oauthAccount`）
- `CL_NO_KILL=1` — 切換前不關掉正在跑的 `claude`

## 安全性

- 若目前帳號還沒被存成 profile，切換會拒絕覆寫它（用 `--force` 可強制）。這能避免你不小心弄丟還沒儲存的登入狀態。
- profile 檔含長期有效的 refresh token — 在 Unix 上 profile 目錄會建成 `chmod 700`、檔案 `chmod 600`。`.gitignore` 會把 profile 與匯出的備份檔擋在版控之外。
- 在 Windows 上，`cl` 會把 `.credentials.json` 寫成 **不含 BOM 的 UTF-8**。BOM 會讓 Claude Code 的 Node 讀取器把 session 當成已登出，所以這點會自動處理 — 別用會加 BOM 的編輯器手動編輯這個檔。
- 在 `claude` 程序還在跑時切換，會在它下一次呼叫 API 時改掉那個 session 的權杖，所以 `cl use` / `cl switch` 會先關掉正在跑的 `claude`。

## Windows

`bin/cl.ps1` 用 PowerShell 鏡射了同樣的指令與 profile 結構（不需要 `jq` —
使用內建的 `ConvertFrom-Json`）。已在 Windows 11 搭配
Windows PowerShell 5.1 驗證 — `cl import` / `cl use` / `cl switch` 全部正常。

`install-oneliner.ps1` 會把 repo clone 到 `%USERPROFILE%\claude-auth-switcher`
（可用 `$env:CL_DEST` / `$env:CL_REPO` 覆寫），接著 `install.ps1` 把 `cl`
接進你的 Windows PowerShell 5.1 與 PowerShell 7 兩個設定檔，所以不論你用
哪個 host 啟動都能運作。

設計細節請見 `docs/superpowers/specs/2026-05-29-claude-auth-switcher-design.md`。

## 授權

MIT — 見 [LICENSE](LICENSE)。
