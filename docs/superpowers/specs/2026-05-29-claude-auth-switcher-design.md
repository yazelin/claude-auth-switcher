# claude-auth-switcher 設計 spec

- 日期:2026-05-29
- 指令名:`cl`
- Repo 名:`claude-auth-switcher`
- 參照前作:[codex-auth-switcher](https://github.com/yazelin/codex-auth-switcher)

## 1. 目的

在同一台機器上管理多個 Claude 訂閱帳號(個人 / 公司,額度各自獨立),不必反覆登出登入即可切換目前 active 的帳號。對齊 codex-auth-switcher 的「共享設定、只換認證」哲學。

## 2. 使用情境與已定範圍

- 使用者有兩個 Claude 訂閱帳號(個人 + 公司),額度分開。
- 同一時間只用一個帳號。會開多個終端機,但都是同一個帳號 —— **不需要**「一邊公司一邊個人」的同時並行,因此**不做** runtime 隔離(不需要 `CLAUDE_CONFIG_DIR` per-profile home)。
- 第一版平台:**Linux + Windows**。macOS(走 Keychain)本版不做,但架構保留可換的憑證讀寫抽象層。
- 第一版功能層級:**核心 + 加值**(不含 limit-hook 自動切換,留待第二版)。

## 3. 關鍵技術前提(已實測確認)

Linux 上 Claude Code 的憑證在 `~/.claude/.credentials.json`(明文 JSON),結構:

```
claudeAiOauth: { accessToken, refreshToken, expiresAt(ms), subscriptionType, rateLimitTier, scopes }
mcpOAuth:      { <plugin:...>: {...}, ... }   # MCP server 的 OAuth token,與帳號無關
```

- **帳號 token 與 MCP token 同檔混存。** 切帳號只能動 `claudeAiOauth`,`mcpOAuth` 必須原封不動保留(這是與 codex「整檔換 auth.json」最大的差異)。
- Token 會過期(`expiresAt`),平常由 Claude Code 背景用 `refreshToken` 換新並寫回。本工具也需具備同樣的 refresh 能力。

**(2026-05-29 補:帳號身分跨兩檔)** 登入帳號的「身分」並非只在 `.credentials.json`。另有一份在 `~/.claude.json`(注意:在 home 根目錄,不是 `.claude/` 內):

```
oauthAccount: { accountUuid, emailAddress, organizationUuid, organizationType,
                organizationRateLimitTier, billingType, displayName, ... }
```

- `.credentials.json` 存 **token**,`~/.claude.json` 的 `oauthAccount` 存 **訂閱身分**(帳號 UUID / 組織 / 方案層級 / 計費型態)。
- **只換 token 不換 `oauthAccount` 會造成兩檔指向不同帳號**:Claude Code 拿到 A 帳號的 token 卻看到 B 帳號的訂閱身分,無法對上 → **fallback 成 API 計費**(帳號名稱可能還顯示舊的)。這是實測踩到的 bug。
- 因此 `cl import` 必須一併把 `oauthAccount` 存進 profile(`<name>.account.json`),`cl use` 切換時必須把它寫回 `~/.claude.json`(只覆寫 `oauthAccount`,保留 `projects` / 歷史等其餘鍵)。
- `~/.claude.json` 很大且 Windows PowerShell 5.1 的 `ConvertFrom-Json` 不一定能解析;`cl.ps1` 改用「字串掃描配對大括號」做外科式替換,不整檔重新序列化。bash 端用 jq 直接 `.oauthAccount = $a`。
- 環境變數 `CL_ACCOUNT` 可覆寫 `~/.claude.json` 路徑。

即時用量查詢(已實測可用,純 curl):

```
GET https://api.anthropic.com/api/oauth/usage
  Authorization: Bearer <accessToken>
  anthropic-beta: oauth-2025-04-20
回傳: { five_hour:{utilization,resets_at}, seven_day:{...}, seven_day_opus, seven_day_sonnet, ... }
```

Token refresh(已找出,未實際觸發以免輪替當前 session 憑證):

```
POST https://platform.claude.com/v1/oauth/token
  body(JSON): { grant_type:"refresh_token", refresh_token, client_id:"9d1c250a-e61b-44d9-88ed-5944d1962f5e" }
回傳: { access_token, refresh_token(輪替), expires_in }
```

## 4. 必須先驗證的未知數

**Windows 上 Claude Code 憑證的儲存位置與格式。** 推測為 `%USERPROFILE%\.claude\.credentials.json` 明文,但**不確定是否有 DPAPI 加密**。實作 Windows(`cl.ps1`)的讀寫前,必須先在實體 Windows 機器上實測確認;此結果會決定 `cl.ps1` 的憑證讀寫實作。在驗證前,Windows 路徑的實作步驟標記為 blocked。

## 5. 架構

### Profile store

- 目錄:`~/.claude_auth_profiles/`(環境變數 `CL_PROFILES_DIR` 可覆寫)
- `<name>.json` — 只存該帳號的 `claudeAiOauth` 物件
- `<name>.usage.json` — 該帳號最近一次拉到的即時用量(供 `list` 快速顯示;可選)
- `current` — 純文字,記錄目前 active 的 profile 名稱
- `.lock` — 切換時建立的鎖目錄,避免兩個切換動作互踩

### 核心切換流程(`cl use <name>`)

1. 取得 `.lock`(已鎖則報錯退出)。
2. 讀 `~/.claude/.credentials.json`,把目前的 `claudeAiOauth.refreshToken` 與所有 profile 檔比對找出歸屬。**若目前 active 帳號不對應任何已存 profile**,代表它尚未被 import —— 切換會覆蓋掉它導致需重登,因此此時必須先警告並中止(可用 `-y` / `--force` 確認後才繼續)。
3. 讀 `<name>.json` 的 `claudeAiOauth`。
4. 若該 token 已過期(`expiresAt < now + buffer`),先 refresh 並把新 token 寫回 `<name>.json`。
5. 用 merge 寫回 `~/.claude/.credentials.json`:只覆寫 `claudeAiOauth`,保留 `mcpOAuth` 與其他鍵。
6. 更新 `current`。
7. 釋放 `.lock`。

### 平台抽象

`bin/cl`(bash + jq)與 `bin/cl.ps1`(PowerShell + 內建 ConvertFrom-Json,不依賴 jq)兩套實作,共用同一份 profile 目錄與檔案格式。憑證的「讀目前 / 寫回」抽成各平台一個函式,日後加 macOS Keychain 只需補該層。

## 6. 指令集(第一版)

```
cl import <name>      把目前 ~/.claude 的 claudeAiOauth 存成名為 <name> 的 profile
cl use <name>         切換 active 帳號(只 merge claudeAiOauth 回 credentials.json)
cl switch             互動式選單切換;若偵測到 claude 正在跑,先警告(可 -y 略過)
cl list               列出 profiles、標示 active、顯示用量 %(5h / 週)與重置時間
cl usage [name|--all] 即時拉用量並更新快取;不帶參數查 active
cl current            印出目前 active profile 名稱
cl remove <name>      刪除一個 profile
cl export <a.tgz>     備份所有 profiles 成 tar.gz
cl restore <a.tgz>    從 tar.gz 還原
cl doctor             顯示路徑、claude 行程狀態、profile 摘要、平台偵測結果
cl help               用法
```

環境變數:`CL_PROFILES_DIR`(預設 `~/.claude_auth_profiles`)、`CLAUDE_CRED`(預設 `~/.claude/.credentials.json`)。

## 7. 檔案結構(對齊 codex-auth-switcher)

```
claude-auth-switcher/
  bin/cl                 # bash 主程式
  bin/cl.ps1             # PowerShell 主程式
  shell/bash.sh          # source 進 ~/.bashrc 的薄包裝(定義 cl 函式)
  shell/powershell.ps1   # PowerShell profile 薄包裝
  install.sh
  install-oneliner.sh
  install.ps1
  install-oneliner.ps1
  README.md
  LICENSE
  docs/                  # GitHub Pages(沿用 codex 結構:_config.yml / index.md / .nojekyll)
  docs/superpowers/specs/2026-05-29-claude-auth-switcher-design.md  # 本 spec
```

## 8. 錯誤處理

- 缺 `~/.claude/.credentials.json`:報錯並提示先用 Claude Code 登入一次。
- 缺 jq(Linux):報錯。
- refresh 失敗(refresh_token 失效):報錯並提示該 profile 需重新 `import`(在該帳號重新登入 Claude Code 後)。
- 切換時取不到 `.lock`:報錯,提示可能有另一個切換在進行,或殘留鎖需手動清。
- usage endpoint 回非預期內容:顯示原始回應供除錯,不中斷其他 profile 的查詢。

## 9. 安全

- profile 目錄 `chmod 700`、profile 檔 `chmod 600`(Linux)。
- Windows 用 `icacls` 把目錄/檔案 ACL 收斂到目前使用者。
- profile 檔含長期有效的 refresh token,屬敏感資料;`.gitignore` 確保 profile 目錄與任何匯出的 tgz 不會被誤 commit。
- 不在 log / stdout 印出完整 token。

## 10. 測試策略

- bash 主程式:用一個假的 `CLAUDE_CRED` 與 `CL_PROFILES_DIR`(指到暫存目錄)跑 import → use → list → remove 的端到端流程,斷言 merge 後 `mcpOAuth` 未被破壞、`claudeAiOauth` 已替換、`current` 正確。
- refresh 流程:用可注入的 token endpoint(環境變數覆寫 URL)對假伺服器測,避免動到真帳號。
- usage 格式化:餵已知 JSON,斷言輸出的 % 與重置時間格式。
- Windows(`cl.ps1`):待第 4 節未知數驗證後再補對應測試。

## 11. 明確不做(YAGNI / 第二版)

- limit-hook 自動偵測額度用盡並切換(第二版)。
- 同時並行多帳號 / runtime 隔離(已確認不需要)。
- macOS Keychain 支援(架構保留,本版不做)。
- GUI / TUI(維持純 CLI)。
