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
