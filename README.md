# AI Secretary - Slack × Claude Code で作る AI 秘書

Slack にメッセージを送ると、Claude Code CLI が応答を返す AI 秘書システムです。

## 特徴

- **Slack 連携**: Socket Mode でリアルタイムにメッセージを受信・返信
- **マルチターン会話**: スレッド単位で会話の文脈を維持
- **複数チャンネル対応**: チャンネルごとに異なる System Prompt を設定可能
- **ファイル対応**: 画像（JPEG, PNG, GIF, WebP）や PDF を添付して質問できる
- **Claude Code の全機能**: コード生成、ファイル操作、Web 検索など Claude Code CLI の機能をそのまま利用

## 前提条件

- **Mac**（macOS）
- **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)** がインストール済みで、`claude` コマンドが使える状態
  - MAX プランまたは API キーが設定済み

## セットアップ

### 1. Slack App を作成する

1. [Slack API](https://api.slack.com/apps) にアクセスし、「Create New App」→「From scratch」を選択
2. App 名（例: `AI Secretary`）とワークスペースを入力して作成

#### Socket Mode を有効化

1. 左メニュー「Socket Mode」→ 有効化
2. App-Level Token を作成（名前: `socket`、Scope: `connections:write`）
3. 生成された `xapp-` で始まるトークンをメモ → **これが `SLACK_APP_TOKEN`**

#### Bot の権限を設定

1. 左メニュー「OAuth & Permissions」→「Scopes」→「Bot Token Scopes」に以下を追加:
   - `chat:write` — メッセージ送信
   - `reactions:write` — リアクション追加・削除
   - `files:read` — ファイル読み取り
   - `users:read` — ユーザー情報取得

#### イベントを設定

1. 左メニュー「Event Subscriptions」→ 有効化
2. 「Subscribe to bot events」に以下を追加:
   - `message.channels` — パブリックチャンネルのメッセージ

3. 左メニュー「Install App」→「Install to Workspace」でインストール
4. 「Bot User OAuth Token」（`xoxb-` で始まる）をメモ → **これが `SLACK_BOT_TOKEN`**

#### Bot をチャンネルに追加

1. Slack で AI 秘書用のチャンネルを作成（例: `#ai-secretary`）
2. チャンネルにボットを招待: `/invite @AI Secretary`
3. チャンネルIDを取得（チャンネル名を右クリック →「リンクをコピー」→ URL 末尾の `C...` がチャンネルID）

### 2. リポジトリをクローン

```bash
git clone https://github.com/euglena1215/ai-secretary.git
cd ai-secretary
```

### 3. セットアップを実行

```bash
bin/bootstrap
```

Homebrew、rbenv、Ruby、gem を自動でインストールします。

### 4. 環境変数を設定

`.env.development` を編集して、Slack のトークンとチャンネルIDを設定します:

```bash
# .env.development

# ステップ1でメモしたトークン
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_APP_TOKEN=xapp-your-app-token

# チャンネル1（必須）
SLACK_CHANNEL_1=C01XXXXXX
SLACK_CHANNEL_1_NAME=ai-secretary
```

### 5. System Prompt をカスタマイズ（任意）

`config/prompts/channel_1.txt` を編集して、ボットの振る舞いを設定します:

```
あなたは便利なAI秘書です。
ユーザーの質問や依頼に丁寧に対応してください。
```

チャンネルごとに異なる System Prompt を設定したい場合は、`channel_2.txt`, `channel_3.txt` ... と追加し、`.env.development` に対応するチャンネルIDを追加します。

### 6. 起動

```bash
bundle exec ruby bin/start
```

Slack のチャンネルにメッセージを送ると、AI 秘書が応答します。

## 常時稼働させる（任意）

Mac でバックグラウンド常時稼働 + 自動再起動したい場合は、macOS の launchd を使います。

### 1. 本番用の環境変数を作成

```bash
cp .env.example .env.production
# .env.production を編集
```

### 2. plist ファイルを作成

```bash
cat > ~/Library/LaunchAgents/com.ai-secretary.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ai-secretary</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(rbenv which ruby)</string>
        <string>$(pwd)/bin/start</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$(pwd)</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>APP_ENV</key>
        <string>production</string>
        <key>PATH</key>
        <string>$(dirname $(rbenv which ruby)):$PATH</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$(pwd)/log/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$(pwd)/log/launchd.err</string>
</dict>
</plist>
EOF
```

> 注: 上記の `$(pwd)` や `$(rbenv which ruby)` は実行時に展開されます。生成後に plist の中身を確認してパスが正しいことを確認してください。

### 3. 起動

```bash
mkdir -p log
launchctl load ~/Library/LaunchAgents/com.ai-secretary.plist
```

### 停止

```bash
launchctl unload ~/Library/LaunchAgents/com.ai-secretary.plist
```

## 複数チャンネルの設定例

チャンネルごとに異なる System Prompt と作業ディレクトリを設定できます:

```bash
# .env.development

SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...

# 一般的な質問用
SLACK_CHANNEL_1=C01XXXXXX
SLACK_CHANNEL_1_NAME=general

# コーディング用（特定のプロジェクトを操作させる）
SLACK_CHANNEL_2=C02YYYYYY
SLACK_CHANNEL_2_NAME=coding
SLACK_CHANNEL_2_WORKDIR=/path/to/your/project
```

対応する System Prompt:
- `config/prompts/channel_1.txt` — 一般的な質問用のプロンプト
- `config/prompts/channel_2.txt` — コーディング用のプロンプト

## Tips: フィードバックチャンネルを作ろう

AI 秘書を使っていると「こういう機能がほしい」「この挙動を変えたい」という改善要望が出てきます。そのときに便利なのが **フィードバック専用チャンネル** です。

フィードバックチャンネルの System Prompt に「改善要望をヒアリングして GitHub Issue を作成し、承認されたら実装して PR を出す」という振る舞いを設定すると、AI 秘書自身が PM（プロダクトマネージャー）として動いてくれます。

**フロー:**
1. フィードバックチャンネルで「〇〇な機能がほしい」と投稿
2. AI 秘書が要件をヒアリング（不明点を質問してくれる）
3. 要件がまとまったら GitHub Issue を作成
4. 承認すると、ブランチを切って実装 → PR を作成

これにより **「要望を伝えるだけで、AI が Issue 作成から実装・PR 作成まで一気通貫でやってくれる」** という開発サイクルが回ります。AI 秘書が自分自身を改善していく仕組みです。

設定例:

```bash
# .env.development に追加
SLACK_CHANNEL_2=C02YYYYYY
SLACK_CHANNEL_2_NAME=feedback
SLACK_CHANNEL_2_WORKDIR=/path/to/this/repo  # このリポジトリ自体を指定
```

`config/prompts/channel_2.txt` にフィードバック用のプロンプトを書けば完成です。サンプルとして [`config/prompts/feedback_example.txt`](config/prompts/feedback_example.txt) を用意しているので、コピーして使ってください:

```bash
cp config/prompts/feedback_example.txt config/prompts/channel_2.txt
```

## アーキテクチャ

```
bin/start                       エントリポイント
bin/bootstrap                   セットアップスクリプト
lib/slack_bot.rb                Socket Mode でイベント受信・返信
lib/claude_executor.rb          Claude CLI をサブプロセスで実行
lib/session_store.rb            SQLite でスレッド⇔セッションを管理
lib/channel_router.rb           チャンネルID → System Prompt のルーティング
lib/database.rb                 SQLite wrapper
lib/event_deduplicator.rb       イベント重複排除
lib/pending_notification_store.rb 再起動時の未送信メッセージ管理
lib/active_reaction_store.rb    リアクション状態管理
lib/slack_mrkdwn_converter.rb   Markdown → Slack 記法変換
config/prompts/                 チャンネル別 System Prompt
```

## ライセンス

MIT
