# frozen_string_literal: true

require "sqlite3"

module Database
  def self.open(db_path)
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA busy_timeout=5000")
    db
  end
end
