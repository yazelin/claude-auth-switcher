# Claude Auth Switcher

[繁體中文](README.md) · [English](README.en.md) · **日本語**

1台のマシンで複数の Claude Code サブスクリプションアカウントを管理できます。
ログアウトして再ログインすることなく、アクティブなアカウントを瞬時に切り替えられます。**Windows**、**Linux**、**macOS** に対応しています。

**[完全ガイド → yazelin.github.io/claude-auth-switcher](https://yazelin.github.io/claude-auth-switcher/ja/)**

[codex-auth-switcher](https://github.com/yazelin/codex-auth-switcher) の姉妹プロジェクトです。同じ発想を Claude Code 向けにしたものです。

## クイックインストール

**Windows PowerShell** — 任意の PowerShell ウィンドウを開いて貼り付けます:

```powershell
irm https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.ps1 | iex
```

追加の依存関係はありません（組み込みの `ConvertFrom-Json` / `Invoke-RestMethod` を使用します）。

**Linux / macOS** — 任意の bash または zsh ターミナルを開いて貼り付けます:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.sh)
```

`git`、`jq`、`curl` が必要です。

どちらのインストーラーもリポジトリをクローンし、`cl` をシェルのプロファイルに組み込み、初回セットアップガイドを表示します。完了後は新しいシェルを開いてください。

## なぜ必要か

たとえば個人用の Claude アカウントと会社用のアカウント（それぞれ独自のサブスクリプションと利用上限を持つ）がある場合、このツールを使えば毎回ログインし直すことなく、1つのコマンドで両者を切り替えられます。

## 仕組み

Claude Code はアカウントの身元を**2つの**ファイルに保持しており、`cl` はその両方を切り替えます:

- `~/.claude/.credentials.json` → `claudeAiOauth` ブロック（**アカウントトークン**）
- `~/.claude.json` → `oauthAccount` ブロック（**サブスクリプションの身元**）

トークンだけを入れ替えると、Claude Code は不整合を検出して密かに **API 課金**へフォールバックしてしまいます。`cl use` は両方のブロックをまとめて書き換えるため、切り替え後も Pro / Max のサブスクリプションが維持されます。期限切れのトークンは切り替え時に自動で更新されます。

それ以外のものはすべて手を付けず、アカウント間で共有されます:

| 項目 | 場所 | 切り替え / 共有 |
|---|---|---|
| `claudeAiOauth`（アカウントトークン） | `~/.claude/.credentials.json` | **プロファイルごとに切り替え** |
| `oauthAccount`（サブスクリプションの身元） | `~/.claude.json` | **プロファイルごとに切り替え** |
| `mcpOAuth`（MCP サーバートークン） | `~/.claude/.credentials.json` | 共有 |
| 設定、履歴、スキル、プラグイン | `~/.claude/` | 共有 |

一度にアクティブになれるアカウントは1つです（切り替えはアクティブなトークンをその場で書き換えます）。

## 初回セットアップ

```bash
# Claude Code でアカウント #1 にログインした状態で:
cl import personal

# ブラウザ OAuth でアカウント #2 を追加（または Claude Code でログインしてから `cl import`）:
cl login company

# 以降は:
cl use company      # アクティブなアカウントを切り替え（先に実行中の claude を終了）
cl switch           # 対話式の切り替え
cl list             # プロファイル、アクティブ印、キャッシュ済み使用量を表示
cl usage --all      # 全アカウントのリアルタイム使用率
```

切り替え後は、いつもどおり `claude` を実行するだけです。覚えておくべきラッパーコマンドはありません。

## コマンド

```
cl login <name>        新しいアカウントを追加（ブラウザ OAuth を開く）
cl import <name>       現在の ~/.claude アカウントをプロファイルとして保存
cl use <name>          アクティブなアカウントを切り替え（先に実行中の claude を終了）
cl switch              対話式の切り替え（先に実行中の claude を終了）
cl kill                実行中のすべての claude プロセスを終了
cl list                プロファイル一覧の表: アクティブ印、email、プラン、キャッシュ済み使用量
cl usage [name|--all]  全アカウントのリアルタイム使用量の表; name = 単一アカウントの詳細
cl current             アクティブなプロファイルを表示
cl remove <name>       プロファイルを削除
cl ps                  実行中の claude プロセスを一覧（本セッションを除く）
cl doctor              パス、claude プロセスの状態、プロファイル概要を表示
cl export <archive>    全プロファイルをバックアップ（Windows .zip / Linux .tgz）
cl restore <archive>   アーカイブからプロファイルを復元
cl help                このヘルプを表示
```

`cl use` は `--force`（現在のアカウントがまだ保存されていなくても切り替える）と
`--no-kill`（実行中の `claude` を先に終了しない。または `CL_NO_KILL=1` を設定）を受け付けます。

### 切り替えの詳細

`cl switch` はプロファイルを一覧表示し、番号の入力を求めます:

```
select a profile:
  1) personal
  2) company
choice: 2
killed 1 running claude process(es) before switching
switched to 'company'
```

**実行中の `claude` セッションは、次の API 呼び出し時にキャッシュ済みトークンを書き戻します**。これにより切り替えが密かに取り消されてしまう恐れがあります。そのため `cl use` と `cl switch` は、認証情報ファイルを入れ替える前に稼働中の `claude` プロセスを終了します。`cl` を起動したプロセス（およびその祖先）は決して終了されないため、Claude セッションの内側から `cl` を実行しても、切り替えの途中でそのセッションが終了することはありません。

## 使用量

`cl list` は整列された表を出力します。各プロファイルのキャッシュ済み使用量を使い、1アカウントにつき1行で表示します:

```
CURRENT  PROFILE      EMAIL                  PLAN   USAGE
*        personal     ya***@gmail.com        max    5h 42% used @14:00 | wk 18% used @06/02
         company      ya***@company.com      pro    5h 7% used @09:00 | wk 55% used @06/05
```

単なる `cl list` はネットワークにアクセスしません。`cl usage`（引数なし、または `--all`）は全アカウントの使用量をリアルタイムで更新してから同じ表を出力するので、アカウントを横並びで比較できます。`cl usage <name>` は指定したアカウントのみを取得し、バケットごとの詳細を表示します:

```
personal:
5h               42% used   reset 05/29 14:00
weekly           18% used   reset 06/02 09:00
weekly-opus       3% used   reset 06/02 09:00
weekly-sonnet    27% used   reset 06/02 09:00
```

パーセンテージは**使用済み**であり、残量ではありません（残量を表示する codex-auth-switcher とは逆です）。email は表示用にマスクされます。

## 環境変数

- `CL_PROFILES_DIR` — プロファイルの保存先（デフォルト `~/.claude_auth_profiles`）
- `CL_CRED` — 認証情報ファイル（デフォルト `~/.claude/.credentials.json`）
- `CL_ACCOUNT` — アカウント身元ファイル（デフォルト `~/.claude.json`、`oauthAccount` を保持）
- `CL_NO_KILL=1` — 切り替え前に実行中の `claude` を終了しない

## 安全性

- 現在のアカウントがまだプロファイルとして保存されていない場合、切り替えは上書きを拒否します（`--force` で上書き可能）。これにより、未保存のログインを誤って失うことを防ぎます。
- プロファイルファイルには長期間有効なリフレッシュトークンが含まれます。Unix ではプロファイルディレクトリが `chmod 700`、ファイルが `chmod 600` で作成されます。`.gitignore` によりプロファイルとエクスポートしたアーカイブはバージョン管理から除外されます。
- Windows では、`cl` は `.credentials.json` を **BOM なしの UTF-8** で書き込みます。BOM があると Claude Code の Node ベースのリーダーがセッションをログアウト状態と見なすため、これは自動的に処理されます。BOM を付加するエディタで手動編集しないでください。
- `claude` プロセスが実行中に切り替えると、そのセッションのトークンが次の API 呼び出し時に変更されてしまうため、`cl use` / `cl switch` は稼働中の `claude` を先に終了します。

## Windows

`bin/cl.ps1` は PowerShell で同じコマンドとプロファイル構成をそのまま再現します（`jq` への依存はなく、組み込みの `ConvertFrom-Json` を使用します）。Windows 11 + Windows PowerShell 5.1 で検証済みで、`cl import` / `cl use` / `cl switch` はすべて動作します。

`install-oneliner.ps1` はリポジトリを `%USERPROFILE%\claude-auth-switcher` にクローンし（`$env:CL_DEST` / `$env:CL_REPO` で上書き可能）、続いて `install.ps1` が `cl` を Windows PowerShell 5.1 と PowerShell 7 の両方のプロファイルに組み込むため、どちらのホストから起動しても動作します。

設計の詳細は `docs/superpowers/specs/2026-05-29-claude-auth-switcher-design.md` を参照してください。

## ライセンス

MIT — [LICENSE](LICENSE) を参照してください。
