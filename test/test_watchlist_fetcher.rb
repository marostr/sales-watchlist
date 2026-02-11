require "test_helper"
require "watchlist_fetcher"
require "tmpdir"
require "json"

class TestWatchlistFetcherLoadWatchlist < Minitest::Test
  def test_loads_json_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "watchlist.json")
      File.write(path, JSON.generate([
        { "name" => "Alice", "linkedin_id" => "alice123" },
        { "name" => "Bob", "linkedin_id" => "bob456" }
      ]))

      list = WatchlistFetcher.load_watchlist(path)
      assert_equal 2, list.length
      assert_equal "Alice", list[0]["name"]
      assert_equal "bob456", list[1]["linkedin_id"]
    end
  end

  def test_save_watchlist_writes_json
    Dir.mktmpdir do |dir|
      path = File.join(dir, "watchlist.json")
      watchlist = [
        { "name" => "Alice", "linkedin_id" => "alice", "profile_urn" => "URN_ALICE" }
      ]

      WatchlistFetcher.save_watchlist(path, watchlist)

      saved = JSON.parse(File.read(path))
      assert_equal "URN_ALICE", saved[0]["profile_urn"]
    end
  end

  def test_raises_on_missing_file
    assert_raises(Errno::ENOENT) do
      WatchlistFetcher.load_watchlist("/nonexistent/watchlist.json")
    end
  end
end

class TestWatchlistFetcherFetchAll < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @store = WatchlistStore.new(File.join(@dir, "test.db"))
    @client = MockVoyagerClient.new
    @fetcher = WatchlistFetcher.new(@client, @store, delay: 0)
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_fetches_posts_and_comments_for_each_person
    @client.profiles["alice"] = "URN_ALICE"
    @client.posts["URN_ALICE"] = [
      { url: "https://linkedin.com/post/1", content: "Alice post", author_name: "Alice", author_profile: "alice" }
    ]
    @client.comments["URN_ALICE"] = [
      { url: "https://linkedin.com/comment/1", comment_text: "Alice comment",
        author_name: "Alice", author_profile: "alice",
        post_url: "https://linkedin.com/post/99", post_content: "Someone's post",
        post_author_name: "Someone", commented_at: 1000 }
    ]

    watchlist = [{ "name" => "Alice", "linkedin_id" => "alice" }]
    stats = @fetcher.fetch_all(watchlist)

    assert_equal 1, stats[:posts_fetched]
    assert_equal 1, stats[:comments_fetched]
    assert_equal 1, stats[:posts_inserted]
    assert_equal 1, stats[:comments_inserted]

    assert_equal 1, @store.unprocessed_posts.length
    assert_equal 1, @store.unprocessed_comments.length
  end

  def test_handles_multiple_people
    @client.profiles["alice"] = "URN_ALICE"
    @client.profiles["bob"] = "URN_BOB"
    @client.posts["URN_ALICE"] = [{ url: "https://linkedin.com/post/1", content: "A", author_name: "Alice", author_profile: "alice" }]
    @client.posts["URN_BOB"] = [{ url: "https://linkedin.com/post/2", content: "B", author_name: "Bob", author_profile: "bob" }]
    @client.comments["URN_ALICE"] = []
    @client.comments["URN_BOB"] = []

    watchlist = [
      { "name" => "Alice", "linkedin_id" => "alice" },
      { "name" => "Bob", "linkedin_id" => "bob" }
    ]
    stats = @fetcher.fetch_all(watchlist)

    assert_equal 2, stats[:posts_fetched]
    assert_equal 2, stats[:posts_inserted]
    assert_equal 2, @store.unprocessed_posts.length
  end

  def test_skips_person_on_profile_not_found
    @client.profiles["alice"] = "URN_ALICE"
    @client.posts["URN_ALICE"] = [{ url: "https://linkedin.com/post/1", content: "A", author_name: "Alice", author_profile: "alice" }]
    @client.comments["URN_ALICE"] = []
    # bob not in profiles -> will raise ProfileNotFound

    watchlist = [
      { "name" => "Bob", "linkedin_id" => "bob" },
      { "name" => "Alice", "linkedin_id" => "alice" }
    ]

    output = capture_io { @fetcher.fetch_all(watchlist) }
    stderr = output[1]
    assert_match(/bob.*not found/i, stderr)
    assert_equal 1, @store.unprocessed_posts.length
  end

  def test_skips_resolve_when_profile_urn_present
    @client.posts["URN_ALICE"] = [{ url: "https://linkedin.com/post/1", content: "A", author_name: "Alice", author_profile: "alice" }]
    @client.comments["URN_ALICE"] = []
    # Note: NOT adding alice to @client.profiles — resolve_profile would raise ProfileNotFound

    watchlist = [{ "name" => "Alice", "linkedin_id" => "alice", "profile_urn" => "URN_ALICE" }]
    stats = @fetcher.fetch_all(watchlist)

    assert_equal 1, stats[:posts_fetched]
  end

  def test_resolves_and_sets_profile_urn_when_missing
    @client.profiles["alice"] = "URN_ALICE"
    @client.posts["URN_ALICE"] = [{ url: "https://linkedin.com/post/1", content: "A", author_name: "Alice", author_profile: "alice" }]
    @client.comments["URN_ALICE"] = []

    watchlist = [{ "name" => "Alice", "linkedin_id" => "alice" }]
    @fetcher.fetch_all(watchlist)

    assert_equal "URN_ALICE", watchlist[0]["profile_urn"]
  end

  def test_logs_fetch_to_store
    @client.profiles["alice"] = "URN_ALICE"
    @client.posts["URN_ALICE"] = [{ url: "https://linkedin.com/post/1", content: "A", author_name: "Alice", author_profile: "alice" }]
    @client.comments["URN_ALICE"] = []

    @fetcher.fetch_all([{ "name" => "Alice", "linkedin_id" => "alice" }])

    db = SQLite3::Database.new(File.join(@dir, "test.db"))
    db.results_as_hash = true
    fetches = db.execute("SELECT * FROM fetches")
    assert_equal 1, fetches.length
    assert_equal 1, fetches[0]["posts_fetched"]
  end
end

class MockVoyagerClient
  attr_accessor :profiles, :posts, :comments

  def initialize
    @profiles = {}
    @posts = {}
    @comments = {}
  end

  def resolve_profile(public_id)
    urn = @profiles[public_id]
    raise VoyagerClient::ProfileNotFound, "Profile not found: #{public_id}" unless urn
    urn
  end

  def fetch_posts(urn, count: 20, start: 0)
    @posts.fetch(urn, [])
  end

  def fetch_comments(urn, count: 20, start: 0)
    @comments.fetch(urn, [])
  end
end
