require "test_helper"
require "watchlist_store"
require "tmpdir"

class TestWatchlistStoreInit < Minitest::Test
  def test_creates_tables
    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "test.db")
      WatchlistStore.new(db_path)

      db = SQLite3::Database.new(db_path)
      tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").flatten
      assert_includes tables, "watchlist_posts"
      assert_includes tables, "watchlist_comments"
      assert_includes tables, "fetches"
    end
  end
end

class TestWatchlistStorePostStorage < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @store = WatchlistStore.new(File.join(@dir, "test.db"))
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_store_posts_inserts_new_posts
    posts = [
      { url: "https://linkedin.com/post/1", author_name: "Alice", author_profile: "alice",
        content: "Hello world", posted_at: "2026-02-10T10:00:00Z" },
      { url: "https://linkedin.com/post/2", author_name: "Bob", author_profile: "bob",
        content: "Another post", posted_at: "2026-02-10T11:00:00Z" }
    ]

    count = @store.store_posts(posts)
    assert_equal 2, count
  end

  def test_store_posts_deduplicates_by_url
    post = { url: "https://linkedin.com/post/1", author_name: "Alice", author_profile: "alice",
             content: "Hello", posted_at: nil }

    @store.store_posts([post])
    count = @store.store_posts([post])
    assert_equal 0, count
  end

  def test_store_posts_skips_posts_without_url
    posts = [
      { url: nil, author_name: "Alice", content: "No URL" },
      { url: "https://linkedin.com/post/1", author_name: "Bob", content: "Has URL" }
    ]

    count = @store.store_posts(posts)
    assert_equal 1, count
  end

  def test_unprocessed_posts_returns_only_unprocessed
    @store.store_posts([
      { url: "https://linkedin.com/post/1", author_name: "Alice", author_profile: "alice", content: "Post 1" },
      { url: "https://linkedin.com/post/2", author_name: "Bob", author_profile: "bob", content: "Post 2" }
    ])

    @store.mark_processed_posts(["https://linkedin.com/post/1"])

    posts = @store.unprocessed_posts
    assert_equal 1, posts.length
    assert_equal "https://linkedin.com/post/2", posts[0]["url"]
  end

  def test_mark_processed_posts
    @store.store_posts([
      { url: "https://linkedin.com/post/1", author_name: "Alice", content: "Post 1" }
    ])

    @store.mark_processed_posts(["https://linkedin.com/post/1"])

    posts = @store.unprocessed_posts
    assert_equal 0, posts.length
  end
end

class TestWatchlistStoreCommentStorage < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @store = WatchlistStore.new(File.join(@dir, "test.db"))
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_store_comments_inserts_new_comments
    comments = [
      { url: "https://linkedin.com/comment/1", author_name: "Alice", author_profile: "alice",
        comment_text: "Nice!", post_url: "https://linkedin.com/post/1",
        post_content: "Original post", post_author_name: "Bob",
        commented_at: "2026-02-10T10:00:00Z" }
    ]

    count = @store.store_comments(comments)
    assert_equal 1, count
  end

  def test_store_comments_deduplicates_by_url
    comment = { url: "https://linkedin.com/comment/1", author_name: "Alice",
                comment_text: "Nice!", post_url: nil, post_content: nil,
                post_author_name: nil, commented_at: nil }

    @store.store_comments([comment])
    count = @store.store_comments([comment])
    assert_equal 0, count
  end

  def test_unprocessed_comments_returns_only_unprocessed
    @store.store_comments([
      { url: "https://linkedin.com/comment/1", author_name: "Alice",
        comment_text: "Comment 1", commented_at: nil },
      { url: "https://linkedin.com/comment/2", author_name: "Bob",
        comment_text: "Comment 2", commented_at: nil }
    ])

    @store.mark_processed_comments(["https://linkedin.com/comment/1"])

    comments = @store.unprocessed_comments
    assert_equal 1, comments.length
    assert_equal "https://linkedin.com/comment/2", comments[0]["url"]
  end
end

class TestWatchlistStoreQueryByAuthor < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @store = WatchlistStore.new(File.join(@dir, "test.db"))
    @store.store_posts([
      { url: "https://linkedin.com/post/1", author_name: "Alice", author_profile: "alice", content: "Alice post" },
      { url: "https://linkedin.com/post/2", author_name: "Bob", author_profile: "bob", content: "Bob post" }
    ])
    @store.store_comments([
      { url: "https://linkedin.com/comment/1", author_name: "Alice", author_profile: "alice",
        comment_text: "Alice comment", post_url: "https://linkedin.com/post/99", post_content: "Some post", commented_at: 1000 },
      { url: "https://linkedin.com/comment/2", author_name: "Bob", author_profile: "bob",
        comment_text: "Bob comment", post_url: "https://linkedin.com/post/88", post_content: "Other post", commented_at: 2000 }
    ])
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_posts_by_author
    posts = @store.posts_by_author("alice")
    assert_equal 1, posts.length
    assert_equal "Alice post", posts[0]["content"]
  end

  def test_comments_by_author
    comments = @store.comments_by_author("alice")
    assert_equal 1, comments.length
    assert_equal "Alice comment", comments[0]["comment_text"]
  end

  def test_returns_empty_for_unknown_author
    assert_equal [], @store.posts_by_author("nobody")
    assert_equal [], @store.comments_by_author("nobody")
  end
end

class TestWatchlistStoreTimeSince < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @store = WatchlistStore.new(File.join(@dir, "test.db"))

    @store.store_posts([
      { url: "https://linkedin.com/post/old", author_name: "Alice", author_profile: "alice",
        content: "Old post", posted_at: "2026-02-08T10:00:00Z" },
      { url: "https://linkedin.com/post/recent", author_name: "Bob", author_profile: "bob",
        content: "Recent post", posted_at: "2026-02-10T10:00:00Z" }
    ])

    @store.store_comments([
      { url: "https://linkedin.com/comment/old", author_name: "Alice", author_profile: "alice",
        comment_text: "Old comment", post_url: "https://linkedin.com/post/99",
        post_content: "Original", post_author_name: "Eve", commented_at: "2026-02-08T10:00:00Z" },
      { url: "https://linkedin.com/comment/recent", author_name: "Bob", author_profile: "bob",
        comment_text: "Recent comment", post_url: "https://linkedin.com/post/88",
        post_content: "Other", post_author_name: "Eve", commented_at: "2026-02-10T10:00:00Z" }
    ])
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_posts_since_returns_posts_after_cutoff
    cutoff = "2026-02-09T00:00:00Z"
    posts = @store.posts_since(cutoff)
    assert_equal 1, posts.length
    assert_equal "Recent post", posts[0]["content"]
  end

  def test_posts_since_returns_all_when_cutoff_is_old
    cutoff = "2026-02-01T00:00:00Z"
    posts = @store.posts_since(cutoff)
    assert_equal 2, posts.length
  end

  def test_posts_since_includes_processed_items
    @store.mark_processed_posts(["https://linkedin.com/post/recent"])
    cutoff = "2026-02-09T00:00:00Z"
    posts = @store.posts_since(cutoff)
    assert_equal 1, posts.length
    assert_equal "Recent post", posts[0]["content"]
  end

  def test_comments_since_returns_comments_after_cutoff
    cutoff = "2026-02-09T00:00:00Z"
    comments = @store.comments_since(cutoff)
    assert_equal 1, comments.length
    assert_equal "Recent comment", comments[0]["comment_text"]
  end

  def test_comments_since_includes_processed_items
    @store.mark_processed_comments(["https://linkedin.com/comment/recent"])
    cutoff = "2026-02-09T00:00:00Z"
    comments = @store.comments_since(cutoff)
    assert_equal 1, comments.length
    assert_equal "Recent comment", comments[0]["comment_text"]
  end

  def test_posts_since_returns_empty_when_nothing_matches
    cutoff = "2026-02-11T00:00:00Z"
    assert_equal [], @store.posts_since(cutoff)
  end

  def test_comments_since_returns_empty_when_nothing_matches
    cutoff = "2026-02-11T00:00:00Z"
    assert_equal [], @store.comments_since(cutoff)
  end
end

class TestWatchlistStoreFetchLog < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @store = WatchlistStore.new(File.join(@dir, "test.db"))
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_log_fetch_records_stats
    @store.log_fetch(posts_fetched: 10, comments_fetched: 5, posts_inserted: 8, comments_inserted: 3)

    db = SQLite3::Database.new(File.join(@dir, "test.db"))
    db.results_as_hash = true
    rows = db.execute("SELECT * FROM fetches")
    assert_equal 1, rows.length
    assert_equal 10, rows[0]["posts_fetched"]
    assert_equal 5, rows[0]["comments_fetched"]
    assert_equal 8, rows[0]["posts_inserted"]
    assert_equal 3, rows[0]["comments_inserted"]
  end
end
