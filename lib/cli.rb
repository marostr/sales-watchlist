require "optparse"
require "json"
require "voyager_client"
require "watchlist_store"
require "watchlist_fetcher"

class CLI
  DEFAULT_WATCHLIST = "watchlist.json"
  DEFAULT_CONTEXT = "sales_context.md"

  def self.run(args, jsessionid: nil, li_at: nil, db_path: nil)
    db_path ||= ENV.fetch("WATCHLIST_DB_PATH", "watchlist.db")
    command = args.shift

    case command
    when "fetch"
      run_fetch(args, jsessionid: jsessionid, li_at: li_at, db_path: db_path)
    when "briefing"
      run_briefing(args, db_path: db_path)
    when "mark-processed"
      run_mark_processed(args, db_path: db_path)
    when "show"
      run_show(args, db_path: db_path)
    else
      $stderr.puts "Usage: sales-watchlist <fetch|briefing|mark-processed>"
      exit 1
    end
  end

  DEFAULT_COOKIES = File.expand_path("~/.linkedin-feed/cookies.env")

  def self.run_fetch(args, jsessionid:, li_at:, db_path:)
    watchlist_path = DEFAULT_WATCHLIST
    cookies_path = nil

    OptionParser.new do |opts|
      opts.on("--watchlist PATH") { |v| watchlist_path = v }
      opts.on("--cookies PATH") { |v| cookies_path = v }
    end.parse!(args)

    jsessionid, li_at = load_cookies(jsessionid, li_at, cookies_path)

    unless jsessionid && li_at
      $stderr.puts "Provide cookies via --cookies PATH, cookies.txt, or LINKEDIN_JSESSIONID/LINKEDIN_LI_AT env vars."
      exit 1
    end

    client = VoyagerClient.new(jsessionid, li_at)
    store = WatchlistStore.new(db_path)
    fetcher = WatchlistFetcher.new(client, store)
    watchlist = WatchlistFetcher.load_watchlist(watchlist_path)

    stats = fetcher.fetch_all(watchlist)
    WatchlistFetcher.save_watchlist(watchlist_path, watchlist)

    puts "Posts fetched:      #{stats[:posts_fetched]}"
    puts "Comments fetched:   #{stats[:comments_fetched]}"
    puts "Posts inserted:     #{stats[:posts_inserted]}"
    puts "Comments inserted:  #{stats[:comments_inserted]}"
  end

  def self.run_briefing(args, db_path:)
    context_path = nil

    OptionParser.new do |opts|
      opts.on("--context PATH") { |v| context_path = v }
    end.parse!(args)

    store = WatchlistStore.new(db_path)
    posts = store.unprocessed_posts
    comments = store.unprocessed_comments

    sales_context = if context_path && File.exist?(context_path)
      File.read(context_path)
    end

    output = {
      posts: posts,
      comments: comments,
      sales_context: sales_context
    }

    puts JSON.pretty_generate(output)
  end

  def self.run_show(args, db_path:)
    linkedin_id = args.shift
    unless linkedin_id
      $stderr.puts "Usage: sales-watchlist show <linkedin_id>"
      exit 1
    end

    store = WatchlistStore.new(db_path)
    posts = store.posts_by_author(linkedin_id)
    comments = store.comments_by_author(linkedin_id)

    puts JSON.pretty_generate(posts: posts, comments: comments)
  end

  def self.load_cookies(jsessionid, li_at, cookies_path)
    return [jsessionid, li_at] if jsessionid && li_at

    path = cookies_path || (File.exist?(DEFAULT_COOKIES) ? DEFAULT_COOKIES : nil)
    if path && File.exist?(path)
      File.readlines(path).each do |line|
        line = line.strip.sub(/\Aexport\s+/, "")
        key, value = line.split("=", 2)
        next unless value

        value = value.strip.gsub(/\A["']|["']\z/, "")
        case key
        when "LINKEDIN_JSESSIONID", "JSESSIONID"
          jsessionid = value
        when "LINKEDIN_LI_AT", "li_at"
          li_at = value
        end
      end
    end

    jsessionid ||= ENV["LINKEDIN_JSESSIONID"]
    li_at ||= ENV["LINKEDIN_LI_AT"]

    [jsessionid, li_at]
  end

  def self.run_mark_processed(args, db_path:)
    mark_all = false

    OptionParser.new do |opts|
      opts.on("--all") { mark_all = true }
    end.parse!(args)

    store = WatchlistStore.new(db_path)

    if mark_all
      post_urls = store.unprocessed_posts.map { |p| p["url"] }
      comment_urls = store.unprocessed_comments.map { |c| c["url"] }

      store.mark_processed_posts(post_urls)
      store.mark_processed_comments(comment_urls)

      puts "Marked #{post_urls.length} post(s) and #{comment_urls.length} comment(s) as processed."
    else
      $stderr.puts "Usage: sales-watchlist mark-processed --all"
      exit 1
    end
  end
end
