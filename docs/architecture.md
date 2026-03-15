# アーキテクチャ

## 全体構成図

```
┌─────────────────────────────────────────────────────────────────┐
│  Mac (常時稼働)                                                  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  bin/start (エントリポイント)                               │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────────────────────┐    │   │
│  │  │  SlackBot                                        │    │   │
│  │  │                                                  │    │   │
│  │  │  ┌─────────────────┐   ┌─────────────────────┐  │    │   │
│  │  │  │ Socket Mode     │   │ Slack Web Client     │  │    │   │
│  │  │  │ (イベント受信)    │   │ (メッセージ送信)      │  │    │   │
│  │  │  └────────┬────────┘   └──────────┬──────────┘  │    │   │
│  │  │           │                       │             │    │   │
│  │  │  ┌────────▼──────────────────┐    │             │    │   │
│  │  │  │ handle_event              │    │             │    │   │
│  │  │  │  ├ EventDeduplicator      │    │             │    │   │
│  │  │  │  └ ChannelRouter          │    │             │    │   │
│  │  │  └───────────────────────────┘    │             │    │   │
│  │  │                                   │             │    │   │
│  │  │  ┌───────────────────────────┐    │             │    │   │
│  │  │  │ process_message           │    │             │    │   │
│  │  │  │  ├ ファイルダウンロード     │    │             │    │   │
│  │  │  │  ├ SessionStore           │    │             │    │   │
│  │  │  │  ├ ClaudeExecutor ────────│────│── claude CLI│    │   │
│  │  │  │  └ SlackMrkdwnConverter   │    │             │    │   │
│  │  │  └───────────────────────────┘    │             │    │   │
│  │  └──────────────────────────────────-┘             │    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────┐  ┌──────────────────────────────────────┐    │
│  │ SQLite DB    │  │ config/prompts/                       │    │
│  │ (db/*.sqlite3│  │  ├ channel_1.txt (System Prompt)      │    │
│  │  sessions    │  │  ├ channel_2.txt                      │    │
│  │  events      │  │  └ ...                                │    │
│  │  reactions   │  └──────────────────────────────────────┘    │
│  └──────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘
        │                                          │
        │  WebSocket (Socket Mode)                 │  サブプロセス
        ▼                                          ▼
┌───────────────┐                          ┌───────────────┐
│  Slack API    │                          │  Claude Code  │
│               │                          │  CLI          │
└───────────────┘                          └───────────────┘
```

## コンポーネント詳細

### エントリポイント

#### `bin/start`
アプリケーションの起動スクリプト。以下を行う:
1. `.env` ファイルから環境変数を読み込む
2. 全コンポーネントを初期化して SlackBot に注入（DI）
3. `bot.start` でイベントループを開始

### コア

#### `SlackBot` (`lib/slack_bot.rb`)
システムの中心。Slack との通信を管理し、メッセージ処理を制御する。

- **Socket Mode 接続**: WebSocket で Slack からリアルタイムにイベントを受信
- **メッセージ処理**: 受信したメッセージを非同期に処理
- **ファイル処理**: 添付ファイル（画像・PDF）をダウンロードしてローカルに保存し、Claude に渡す
- **リアクション管理**: 処理中はメッセージにリアクションを付与し、完了時に削除

#### `ClaudeExecutor` (`lib/claude_executor.rb`)
Claude Code CLI をサブプロセスとして実行する。

- **コマンド構築**: `claude -p <query> --output-format json --dangerously-skip-permissions` を基本コマンドとして構築
- **セッション継続**: `--resume <session_id>` でスレッド内の会話を継続
- **System Prompt**: `--append-system-prompt` でチャンネル固有のプロンプトを追加
- **タイムアウト**: 30 分でタイムアウトし、TERM → KILL の順でプロセスを終了
- **コンテキスト使用量**: レスポンスからトークン使用量を抽出して返す

#### `ChannelRouter` (`lib/channel_router.rb`)
Slack チャンネルID と設定のマッピングを管理する。

- 環境変数 `SLACK_CHANNEL_1` 〜 `SLACK_CHANNEL_10` から最大 10 チャンネルを登録
- 各チャンネルに対応する設定:
  - **System Prompt**: `config/prompts/channel_N.txt`
  - **チャンネル名**: `SLACK_CHANNEL_N_NAME`（ログ表示用）
  - **作業ディレクトリ**: `SLACK_CHANNEL_N_WORKDIR`（Claude の作業ディレクトリ）

### ストレージ（SQLite）

すべて同一の SQLite ファイル（`db/secretary.sqlite3`）に保存される。テーブルは各 Store クラスの初期化時に自動作成される。

#### `SessionStore` (`lib/session_store.rb`)
スレッド ⇔ Claude セッションの対応を管理する。

| カラム | 説明 |
|--------|------|
| `channel_id` | Slack チャンネルID |
| `thread_ts` | Slack スレッドのタイムスタンプ |
| `claude_session_id` | Claude Code CLI のセッションID |

同じスレッドへのメッセージは同一セッションとして Claude に渡されるため、会話の文脈が維持される。

#### `EventDeduplicator` (`lib/event_deduplicator.rb`)
Slack イベントの重複処理を防ぐ。

- 処理済みの `event_id` を SQLite に記録
- 同一イベントが再配信された場合にスキップ
- 1 時間経過したレコードを自動クリーンアップ（10 分間隔）

#### `ActiveReactionStore` (`lib/active_reaction_store.rb`)
処理中リアクションの状態を追跡する。

- リアクション付与時に記録、削除時に消去
- プロセスがクラッシュした場合、再起動時に孤立リアクションをクリーンアップ

### ユーティリティ

#### `SlackMrkdwnConverter` (`lib/slack_mrkdwn_converter.rb`)
Claude の出力（Markdown）を Slack の mrkdwn 記法に変換する。

| Markdown | Slack mrkdwn |
|----------|-------------|
| `### 見出し` | `*見出し*` |
| `**太字**` | `*太字*` |
| `[テキスト](URL)` | `<URL\|テキスト>` |
| `---` | `━━━━━━━━━━` |
| テーブル | キー: 値 形式に変換 |

#### `Database` (`lib/database.rb`)
SQLite の共通初期化処理。

## 外部依存

| 依存 | 用途 |
|------|------|
| Slack API (Socket Mode) | WebSocket でイベント受信。HTTP API 不要、ファイアウォール設定不要 |
| Claude Code CLI | AI の応答生成。サブプロセスとして実行 |
| SQLite | セッション管理・イベント重複排除。外部 DB サーバー不要 |
