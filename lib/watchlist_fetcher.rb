require "json"
require "voyager_client"
require "watchlist_store"

class WatchlistFetcher
  def self.load_watchlist(path)
    JSON.parse(File.read(path))
  end

  def self.save_watchlist(path, watchlist)
    File.write(path, JSON.pretty_generate(watchlist))
  end

  def initialize(client, store, delay: nil)
    @client = client
    @store = store
    @delay = delay
  end

  def fetch_all(watchlist)
    totals = { posts_fetched: 0, comments_fetched: 0, posts_inserted: 0, comments_inserted: 0 }

    watchlist.each_with_index do |person, i|
      name = person["name"]
      linkedin_id = person["linkedin_id"]

      $stderr.print "Fetching #{name} (#{linkedin_id})... "

      urn = person["profile_urn"]
      unless urn
        begin
          urn = @client.resolve_profile(linkedin_id)
          person["profile_urn"] = urn
        rescue VoyagerClient::ProfileNotFound
          $stderr.puts "not found, skipping"
          next
        end
      end

      sleep(random_delay) if i > 0

      posts = @client.fetch_posts(urn)
      sleep(random_delay)
      comments = @client.fetch_comments(urn)

      posts.each { |p| p[:author_name] = name; p[:author_profile] = linkedin_id }
      comments.each { |c| c[:author_name] = name; c[:author_profile] = linkedin_id }

      posts_inserted = @store.store_posts(posts)
      comments_inserted = @store.store_comments(comments)

      totals[:posts_fetched] += posts.length
      totals[:comments_fetched] += comments.length
      totals[:posts_inserted] += posts_inserted
      totals[:comments_inserted] += comments_inserted

      $stderr.puts "#{posts.length} posts, #{comments.length} comments (#{posts_inserted} new posts, #{comments_inserted} new comments)"
    end

    @store.log_fetch(**totals)
    totals
  end

  private

  def random_delay
    @delay || rand(2.0..5.0)
  end
end
