# frozen_string_literal: true

require_relative "database"

class ActiveReactionStore
  def initialize(db_path: "db/secretary.sqlite3")
    @db = Database.open(db_path)
    create_table
  end

  def save(channel_id:, timestamp:, name:)
    @db.execute(
      "INSERT INTO active_reactions (channel_id, message_ts, reaction_name) VALUES (?, ?, ?)",
      [channel_id, timestamp, name]
    )
  end

  def delete(channel_id:, timestamp:, name:)
    @db.execute(
      "DELETE FROM active_reactions WHERE channel_id = ? AND message_ts = ? AND reaction_name = ?",
      [channel_id, timestamp, name]
    )
  end

  def read_all
    @db.execute("SELECT channel_id, message_ts, reaction_name FROM active_reactions ORDER BY id")
  end

  def clear!
    @db.execute("DELETE FROM active_reactions")
  end

  private

  def create_table
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS active_reactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        message_ts TEXT NOT NULL,
        reaction_name TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end
end
