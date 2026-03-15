# frozen_string_literal: true

require_relative "database"

class EventDeduplicator
  CLEANUP_INTERVAL = 600 # 10 minutes
  EVENT_TTL = 3600 # 1 hour

  def initialize(db_path: "db/secretary.sqlite3")
    @db = Database.open(db_path)
    @last_cleanup_at = Time.now
    create_table
  end

  # @param event_id [String]
  # @return [Boolean] true if the event has already been processed
  def already_processed?(event_id)
    cleanup_if_needed

    row = @db.get_first_row(
      "SELECT 1 FROM processed_events WHERE event_id = ?",
      [event_id]
    )
    return true if row

    @db.execute(
      "INSERT INTO processed_events (event_id) VALUES (?)",
      [event_id]
    )
    false
  end

  private

  def create_table
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS processed_events (
        event_id TEXT PRIMARY KEY,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end

  def cleanup_if_needed
    return if Time.now - @last_cleanup_at < CLEANUP_INTERVAL

    @db.execute(
      "DELETE FROM processed_events WHERE created_at < datetime('now', ?)",
      ["-#{EVENT_TTL} seconds"]
    )
    @last_cleanup_at = Time.now
  end
end
