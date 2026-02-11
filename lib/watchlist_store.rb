require "sqlite3"
require "time"

class WatchlistStore
  def initialize(db_path)
    @db = SQLite3::Database.new(db_path)
    @db.results_as_hash = true
    init_db
  end

  def store_posts(posts)
    now = Time.now.utc.iso8601
    inserted = 0

    posts.each do |p|
      next unless p[:url]

      begin
        @db.execute(
          "INSERT INTO watchlist_posts (url, author_name, author_profile, content, posted_at, fetched_at) VALUES (?, ?, ?, ?, ?, ?)",
          [p[:url], p[:author_name], p[:author_profile], p[:content], p[:posted_at], now]
        )
        inserted += 1
      rescue SQLite3::ConstraintException
        # duplicate URL, skip
      end
    end

    inserted
  end

  def store_comments(comments)
    now = Time.now.utc.iso8601
    inserted = 0

    comments.each do |c|
      next unless c[:url]

      begin
        @db.execute(
          "INSERT INTO watchlist_comments (url, author_name, author_profile, comment_text, post_url, post_content, post_author_name, commented_at, fetched_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [c[:url], c[:author_name], c[:author_profile], c[:comment_text], c[:post_url], c[:post_content], c[:post_author_name], c[:commented_at], now]
        )
        inserted += 1
      rescue SQLite3::ConstraintException
        # duplicate URL, skip
      end
    end

    inserted
  end

  def unprocessed_posts
    @db.execute("SELECT * FROM watchlist_posts WHERE processed = 0 ORDER BY rowid")
  end

  def unprocessed_comments
    @db.execute("SELECT * FROM watchlist_comments WHERE processed = 0 ORDER BY rowid")
  end

  def posts_since(cutoff)
    @db.execute("SELECT * FROM watchlist_posts WHERE posted_at >= ? ORDER BY rowid", [cutoff])
  end

  def comments_since(cutoff)
    @db.execute("SELECT * FROM watchlist_comments WHERE commented_at >= ? ORDER BY rowid", [cutoff])
  end

  def posts_by_author(author_profile)
    @db.execute("SELECT * FROM watchlist_posts WHERE author_profile = ? ORDER BY rowid", [author_profile])
  end

  def comments_by_author(author_profile)
    @db.execute("SELECT * FROM watchlist_comments WHERE author_profile = ? ORDER BY rowid", [author_profile])
  end

  def mark_processed_posts(urls)
    urls.each do |url|
      @db.execute("UPDATE watchlist_posts SET processed = 1 WHERE url = ?", [url])
    end
  end

  def mark_processed_comments(urls)
    urls.each do |url|
      @db.execute("UPDATE watchlist_comments SET processed = 1 WHERE url = ?", [url])
    end
  end

  def log_fetch(posts_fetched:, comments_fetched:, posts_inserted:, comments_inserted:)
    @db.execute(
      "INSERT INTO fetches (started_at, posts_fetched, comments_fetched, posts_inserted, comments_inserted) VALUES (?, ?, ?, ?, ?)",
      [Time.now.utc.iso8601, posts_fetched, comments_fetched, posts_inserted, comments_inserted]
    )
  end

  private

  def init_db
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS watchlist_posts (
        url TEXT PRIMARY KEY,
        author_name TEXT,
        author_profile TEXT,
        content TEXT,
        posted_at TEXT,
        fetched_at TEXT NOT NULL,
        processed INTEGER NOT NULL DEFAULT 0
      )
    SQL

    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS watchlist_comments (
        url TEXT PRIMARY KEY,
        author_name TEXT,
        author_profile TEXT,
        comment_text TEXT,
        post_url TEXT,
        post_content TEXT,
        post_author_name TEXT,
        commented_at TEXT,
        fetched_at TEXT NOT NULL,
        processed INTEGER NOT NULL DEFAULT 0
      )
    SQL

    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS fetches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        posts_fetched INTEGER NOT NULL,
        comments_fetched INTEGER NOT NULL,
        posts_inserted INTEGER NOT NULL,
        comments_inserted INTEGER NOT NULL
      )
    SQL
  end
end
