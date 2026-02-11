require "net/http"
require "json"
require "uri"

class VoyagerClient
  BASE_URL = "https://www.linkedin.com/voyager/api"
  POSTS_QUERY_ID = "voyagerFeedDashProfileUpdates.4af00b28d60ed0f1488018948daad822"
  COMMENTS_QUERY_ID = "voyagerFeedDashProfileUpdates.8f05a4e5ad12d9cb2b56eaa22afbcab9"

  UPDATE_TYPE = "com.linkedin.voyager.dash.feed.Update"
  COMMENT_TYPE = "com.linkedin.voyager.dash.social.Comment"

  class ApiError < StandardError; end
  class ProfileNotFound < ApiError; end

  def initialize(jsessionid, li_at)
    @jsessionid = jsessionid.delete('"')
    @li_at = li_at
  end

  def resolve_profile(public_id)
    data = get("/identity/dash/profiles", "q" => "memberIdentity", "memberIdentity" => public_id)
    included = data.fetch("included", [])
    profile = included.find { |item| item["entityUrn"]&.include?("fsd_profile") }
    raise ProfileNotFound, "Profile not found: #{public_id}" unless profile

    profile["entityUrn"].split(":").last
  end

  def fetch_posts(profile_urn, count: 20, start: 0)
    data = graphql_feed(profile_urn, POSTS_QUERY_ID, count: count, start: start)
    updates = data.fetch("included", []).select { |item| item["$type"] == UPDATE_TYPE }

    updates.filter_map { |update| parse_post(update) }
  end

  def fetch_comments(profile_urn, count: 20, start: 0)
    data = graphql_feed(profile_urn, COMMENTS_QUERY_ID, count: count, start: start)
    included = data.fetch("included", [])

    comments = included.select { |item| item["$type"] == COMMENT_TYPE }
    updates = included.select { |item| item["$type"] == UPDATE_TYPE }

    comments.each_with_index.filter_map do |comment, i|
      update = updates[i]
      parse_comment(comment, update)
    end
  end

  private

  def parse_post(update)
    content = update.dig("commentary", "text", "text")
    return nil unless content

    urn = update.dig("updateMetadata", "urn")
    url = "https://www.linkedin.com/feed/update/#{urn}" if urn

    { url: url, content: content }
  end

  def parse_comment(comment, update)
    comment_text = comment.dig("commentary", "text")
    return nil unless comment_text

    post_content = update&.dig("commentary", "text", "text")
    header = update&.dig("header", "text", "text")
    post_urn = update&.dig("updateMetadata", "urn")
    post_url = "https://www.linkedin.com/feed/update/#{post_urn}" if post_urn

    {
      url: comment["permalink"],
      comment_text: comment_text,
      post_url: post_url,
      post_content: post_content,
      header: header,
      commented_at: comment["createdAt"]
    }
  end

  def graphql_feed(profile_urn, query_id, count:, start:)
    encoded_urn = URI.encode_www_form_component("urn:li:fsd_profile:#{profile_urn}")
    path = "/graphql?includeWebMetadata=true" \
           "&variables=(count:#{count},start:#{start},profileUrn:#{encoded_urn})" \
           "&queryId=#{query_id}"
    get(path)
  end

  def get(path, params = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?

    request = Net::HTTP::Get.new(uri)
    request["Csrf-Token"] = @jsessionid
    request["Accept"] = "application/vnd.linkedin.normalized+json+2.1"
    request["Cookie"] = "JSESSIONID=\"#{@jsessionid}\"; li_at=#{@li_at}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    raise ApiError, "HTTP #{response.code}: #{response.body[0..200]}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
