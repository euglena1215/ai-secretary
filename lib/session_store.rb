# frozen_string_literal: true

require_relative "database"

class SessionStore
  def initialize(db_path: "db/secretary.sqlite3")
    @db = Database.open(db_path)
    create_table
  end

  # @param channel_id [String]
  # @param thread_ts [String]
  # @return [String, nil] session_id or nil
  def find(channel_id:, thread_ts:)
    row = @db.get_first_row(
      "SELECT claude_session_id FROM sessions WHERE channel_id = ? AND thread_ts = ?",
      [channel_id, thread_ts]
    )
    row&.fetch("claude_session_id")
  end

  # @param channel_id [String]
  # @param thread_ts [String]
  # @param session_id [String]
  def save(channel_id:, thread_ts:, session_id:)
    @db.execute(
      <<~SQL,
        INSERT INTO sessions (channel_id, thread_ts, claude_session_id, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT (channel_id, thread_ts)
        DO UPDATE SET claude_session_id = excluded.claude_session_id, updated_at = CURRENT_TIMESTAMP
      SQL
      [channel_id, thread_ts, session_id]
    )
  end

  private

  def create_table
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS sessions (
        channel_id TEXT NOT NULL,
        thread_ts TEXT NOT NULL,
        claude_session_id TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (channel_id, thread_ts)
      )
    SQL
  end
end
