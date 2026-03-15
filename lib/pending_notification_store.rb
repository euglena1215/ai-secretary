# frozen_string_literal: true

require_relative "database"

class PendingNotificationStore
  def initialize(db_path: "db/secretary.sqlite3")
    @db = Database.open(db_path)
    create_table
  end

  def read_all
    @db.execute("SELECT channel_id, thread_ts, message FROM pending_notifications ORDER BY id")
  end

  def clear!
    @db.execute("DELETE FROM pending_notifications")
  end

  private

  def create_table
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS pending_notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        thread_ts TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end
end
