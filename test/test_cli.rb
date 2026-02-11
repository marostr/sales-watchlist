require "test_helper"
require "cli"
require "tmpdir"
require "json"

class TestCliFetch < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @db_path = File.join(@dir, "test.db")
    @watchlist_path = File.join(@dir, "watchlist.json")
    File.write(@watchlist_path, JSON.generate([
      { "name" => "Alice", "linkedin_id" => "alice" }
    ]))

    # Stub the Voyager API calls
    stub_request(:get, /identity\/dash\/profiles/)
      .to_return(status: 200, body: {
        "included" => [{ "entityUrn" => "urn:li:fsd_profile:URN_ALICE" }]
      }.to_json)

    stub_request(:get, /graphql.*4af00b/)
      .to_return(status: 200, body: {
        "included" => [{
          "$type" => "com.linkedin.voyager.dash.feed.Update",
          "updateMetadata" => { "urn" => "urn:li:activity:1" },
          "commentary" => { "text" => { "text" => "Alice post" } }
        }]
      }.to_json)

    stub_request(:get, /graphql.*8f05a4/)
      .to_return(status: 200, body: { "included" => [] }.to_json)
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_fetch_command
    out, _err = capture_io do
      CLI.run(["fetch", "--watchlist", @watchlist_path],
        jsessionid: "ajax:123", li_at: "token", db_path: @db_path)
    end

    assert_match(/Posts fetched/, out)
    assert_match(/1/, out)
  end

  def test_fetch_reads_cookies_from_file
    cookie_path = File.join(@dir, "cookies.txt")
    File.write(cookie_path, "JSESSIONID=\"ajax:123\"\nli_at=token")

    out, _err = capture_io do
      CLI.run(["fetch", "--watchlist", @watchlist_path, "--cookies", cookie_path],
        db_path: @db_path)
    end

    assert_match(/Posts fetched/, out)
  end

  def test_fetch_reads_export_format_cookies
    cookie_path = File.join(@dir, "cookies.env")
    File.write(cookie_path, "export LINKEDIN_JSESSIONID=\"ajax:123\"\nexport LINKEDIN_LI_AT=\"token\"")

    out, _err = capture_io do
      CLI.run(["fetch", "--watchlist", @watchlist_path, "--cookies", cookie_path],
        db_path: @db_path)
    end

    assert_match(/Posts fetched/, out)
  end

  def test_fetch_saves_resolved_urns_to_watchlist
    capture_io do
      CLI.run(["fetch", "--watchlist", @watchlist_path],
        jsessionid: "ajax:123", li_at: "token", db_path: @db_path)
    end

    saved = JSON.parse(File.read(@watchlist_path))
    assert_equal "URN_ALICE", saved[0]["profile_urn"]
  end
end

class TestCliBriefing < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @db_path = File.join(@dir, "test.db")
    @context_path = File.join(@dir, "sales_context.md")
    File.write(@context_path, "I sell widgets to enterprises")

    store = WatchlistStore.new(@db_path)
    store.store_posts([
      { url: "https://linkedin.com/post/1", author_name: "Alice", author_profile: "alice",
        content: "Hello world", posted_at: "2026-02-10T10:00:00Z" }
    ])
    store.store_comments([
      { url: "https://linkedin.com/comment/1", author_name: "Alice", author_profile: "alice",
        comment_text: "Great post!", post_url: "https://linkedin.com/post/99",
        post_content: "Original", post_author_name: "Bob", commented_at: "1000" }
    ])
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_briefing_outputs_json_with_posts_comments_and_context
    out, _err = capture_io do
      CLI.run(["briefing", "--context", @context_path], db_path: @db_path)
    end

    data = JSON.parse(out)
    assert_equal 1, data["posts"].length
    assert_equal 1, data["comments"].length
    assert_equal "I sell widgets to enterprises", data["sales_context"]
    assert_equal "Hello world", data["posts"][0]["content"]
    assert_equal "Great post!", data["comments"][0]["comment_text"]
  end

  def test_briefing_without_context_file
    out, _err = capture_io do
      CLI.run(["briefing"], db_path: @db_path)
    end

    data = JSON.parse(out)
    assert_nil data["sales_context"]
    assert_equal 1, data["posts"].length
  end
end

class TestCliShow < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @db_path = File.join(@dir, "test.db")

    store = WatchlistStore.new(@db_path)
    store.store_posts([
      { url: "https://linkedin.com/post/1", author_name: "Alice", author_profile: "alice", content: "Alice post" },
      { url: "https://linkedin.com/post/2", author_name: "Bob", author_profile: "bob", content: "Bob post" }
    ])
    store.store_comments([
      { url: "https://linkedin.com/comment/1", author_name: "Alice", author_profile: "alice",
        comment_text: "Alice comment", post_url: "https://linkedin.com/post/99",
        post_content: "Original", commented_at: "1000" }
    ])
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_show_outputs_person_posts_and_comments
    out, _err = capture_io do
      CLI.run(["show", "alice"], db_path: @db_path)
    end

    data = JSON.parse(out)
    assert_equal 1, data["posts"].length
    assert_equal "Alice post", data["posts"][0]["content"]
    assert_equal 1, data["comments"].length
    assert_equal "Alice comment", data["comments"][0]["comment_text"]
  end

  def test_show_excludes_other_authors
    out, _err = capture_io do
      CLI.run(["show", "alice"], db_path: @db_path)
    end

    data = JSON.parse(out)
    data["posts"].each { |p| assert_equal "alice", p["author_profile"] }
  end
end

class TestCliMarkProcessed < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @db_path = File.join(@dir, "test.db")

    store = WatchlistStore.new(@db_path)
    store.store_posts([
      { url: "https://linkedin.com/post/1", author_name: "Alice", content: "Post 1" },
      { url: "https://linkedin.com/post/2", author_name: "Bob", content: "Post 2" }
    ])
    store.store_comments([
      { url: "https://linkedin.com/comment/1", author_name: "Alice", comment_text: "Comment 1" }
    ])
  end

  def teardown
    FileUtils.remove_entry @dir
  end

  def test_mark_processed_all
    out, _err = capture_io do
      CLI.run(["mark-processed", "--all"], db_path: @db_path)
    end

    assert_match(/Marked/, out)

    store = WatchlistStore.new(@db_path)
    assert_equal 0, store.unprocessed_posts.length
    assert_equal 0, store.unprocessed_comments.length
  end
end
