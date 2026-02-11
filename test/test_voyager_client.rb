require "test_helper"
require "voyager_client"

class TestVoyagerClientResolveProfile < Minitest::Test
  def setup
    @client = VoyagerClient.new("ajax:123456", "fake_li_at_token")
  end

  def test_resolve_profile_returns_urn_id
    response_body = {
      "included" => [
        {
          "entityUrn" => "urn:li:fsd_profile:ACoAAAvvCuEBFoKo-y6KGmtJ_tVzmV_Bv4YWvwE",
          "firstName" => "Dorota",
          "lastName" => "Piekarska"
        }
      ]
    }.to_json

    stub_request(:get, "https://www.linkedin.com/voyager/api/identity/dash/profiles?q=memberIdentity&memberIdentity=dorotapiekarska")
      .to_return(status: 200, body: response_body)

    urn = @client.resolve_profile("dorotapiekarska")
    assert_equal "ACoAAAvvCuEBFoKo-y6KGmtJ_tVzmV_Bv4YWvwE", urn
  end

  def test_resolve_profile_raises_on_not_found
    stub_request(:get, "https://www.linkedin.com/voyager/api/identity/dash/profiles?q=memberIdentity&memberIdentity=nobody")
      .to_return(status: 200, body: { "included" => [] }.to_json)

    assert_raises(VoyagerClient::ProfileNotFound) do
      @client.resolve_profile("nobody")
    end
  end

  def test_resolve_profile_raises_on_http_error
    stub_request(:get, "https://www.linkedin.com/voyager/api/identity/dash/profiles?q=memberIdentity&memberIdentity=someone")
      .to_return(status: 403, body: "Forbidden")

    assert_raises(VoyagerClient::ApiError) do
      @client.resolve_profile("someone")
    end
  end

  def test_sends_correct_headers
    stub_request(:get, "https://www.linkedin.com/voyager/api/identity/dash/profiles?q=memberIdentity&memberIdentity=test")
      .with(
        headers: {
          "Csrf-Token" => "ajax:123456",
          "Accept" => "application/vnd.linkedin.normalized+json+2.1"
        }
      )
      .to_return(status: 200, body: {
        "included" => [{ "entityUrn" => "urn:li:fsd_profile:ABC123" }]
      }.to_json)

    @client.resolve_profile("test")
  end

  def test_sends_cookies
    stub_request(:get, "https://www.linkedin.com/voyager/api/identity/dash/profiles?q=memberIdentity&memberIdentity=test")
      .with(headers: { "Cookie" => 'JSESSIONID="ajax:123456"; li_at=fake_li_at_token' })
      .to_return(status: 200, body: {
        "included" => [{ "entityUrn" => "urn:li:fsd_profile:ABC123" }]
      }.to_json)

    @client.resolve_profile("test")
  end
end

class TestVoyagerClientFetchPosts < Minitest::Test
  PROFILE_URN = "ACoAAAvvCuEBFoKo-y6KGmtJ_tVzmV_Bv4YWvwE"

  def setup
    @client = VoyagerClient.new("ajax:123456", "fake_li_at_token")
  end

  def test_fetch_posts_returns_parsed_posts
    response_body = {
      "included" => [
        {
          "$type" => "com.linkedin.voyager.dash.feed.Update",
          "updateMetadata" => { "urn" => "urn:li:activity:123" },
          "commentary" => { "text" => { "text" => "Hello world, this is my post" } },
          "header" => nil
        },
        {
          "$type" => "com.linkedin.voyager.dash.identity.profile.Profile",
          "firstName" => "Dorota"
        }
      ]
    }.to_json

    stub_graphql_posts(PROFILE_URN, response_body)

    posts = @client.fetch_posts(PROFILE_URN)
    assert_equal 1, posts.length
    assert_equal "Hello world, this is my post", posts[0][:content]
    assert_equal "https://www.linkedin.com/feed/update/urn:li:activity:123", posts[0][:url]
  end

  def test_fetch_posts_skips_updates_without_commentary
    response_body = {
      "included" => [
        {
          "$type" => "com.linkedin.voyager.dash.feed.Update",
          "updateMetadata" => { "urn" => "urn:li:activity:123" },
          "commentary" => nil,
          "header" => nil
        }
      ]
    }.to_json

    stub_graphql_posts(PROFILE_URN, response_body)

    posts = @client.fetch_posts(PROFILE_URN)
    assert_equal 0, posts.length
  end

  def test_fetch_posts_with_pagination
    response_body = { "included" => [] }.to_json

    stub_request(:get, graphql_url(PROFILE_URN, count: 10, start: 20, query_id: VoyagerClient::POSTS_QUERY_ID))
      .to_return(status: 200, body: response_body)

    @client.fetch_posts(PROFILE_URN, count: 10, start: 20)
  end

  def test_fetch_posts_returns_empty_on_no_updates
    stub_graphql_posts(PROFILE_URN, { "included" => [] }.to_json)

    posts = @client.fetch_posts(PROFILE_URN)
    assert_equal [], posts
  end

  private

  def stub_graphql_posts(urn, body)
    stub_request(:get, graphql_url(urn, count: 20, start: 0, query_id: VoyagerClient::POSTS_QUERY_ID))
      .to_return(status: 200, body: body)
  end

  def graphql_url(urn, count:, start:, query_id:)
    encoded_urn = "urn%3Ali%3Afsd_profile%3A#{urn}"
    "https://www.linkedin.com/voyager/api/graphql?includeWebMetadata=true&variables=(count:#{count},start:#{start},profileUrn:#{encoded_urn})&queryId=#{query_id}"
  end
end
