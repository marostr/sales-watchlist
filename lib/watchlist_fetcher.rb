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

      posts_fetched, posts_inserted = paginated_fetch(urn, name, linkedin_id, :posts)
      sleep(random_delay)
      comments_fetched, comments_inserted = paginated_fetch(urn, name, linkedin_id, :comments)

      totals[:posts_fetched] += posts_fetched
      totals[:comments_fetched] += comments_fetched
      totals[:posts_inserted] += posts_inserted
      totals[:comments_inserted] += comments_inserted

      $stderr.puts "#{posts_fetched} posts, #{comments_fetched} comments (#{posts_inserted} new posts, #{comments_inserted} new comments)"
    end

    @store.log_fetch(**totals)
    totals
  end

  private

  PAGE_SIZE = 20
  MAX_PAGES = 4

  def paginated_fetch(urn, name, linkedin_id, type)
    total_fetched = 0
    total_inserted = 0

    MAX_PAGES.times do |page|
      items = if type == :posts
        @client.fetch_posts(urn, start: page * PAGE_SIZE)
      else
        @client.fetch_comments(urn, start: page * PAGE_SIZE)
      end
      break if items.empty?

      items.each { |item| item[:author_name] = name; item[:author_profile] = linkedin_id }

      inserted = if type == :posts
        @store.store_posts(items)
      else
        @store.store_comments(items)
      end

      total_fetched += items.length
      total_inserted += inserted

      break unless items.length == PAGE_SIZE && items.length == inserted

      sleep(random_delay) if page < MAX_PAGES - 1
    end

    [total_fetched, total_inserted]
  end

  def random_delay
    @delay || rand(2.0..5.0)
  end
end
