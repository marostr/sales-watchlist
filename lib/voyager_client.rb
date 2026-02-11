require "net/http"
require "json"
require "uri"

class VoyagerClient
  BASE_URL = "https://www.linkedin.com/voyager/api"

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

  private

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
