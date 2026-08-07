# frozen_string_literal: true

require 'net/http'
require 'uri'

# Minimal GET/HEAD wrapper with redirect following, so the resolver can stay stdlib-only.
module HttpClient
  # Several podcast hosts serve a bot-blocking page unless the request looks like a browser.
  USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' \
               '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30
  MAX_REDIRECTS = 5

  Response = Struct.new(:status, :headers, :body, :url, keyword_init: true)

  class << self
    def get(url, redirects: MAX_REDIRECTS)
      request(Net::HTTP::Get, url, redirects: redirects)
    end

    def head(url, redirects: MAX_REDIRECTS)
      request(Net::HTTP::Head, url, redirects: redirects)
    end

    # Asks for the first byte. The response's `Content-Range` states the file's true
    # size, which is the only number worth trusting: hosts answer HEAD with 403, with
    # an empty Content-Length, or with a stub describing something else entirely.
    def ranged_get(url, redirects: MAX_REDIRECTS)
      request(Net::HTTP::Get, url, redirects: redirects, headers: { 'Range' => 'bytes=0-0' })
    end

    private

    def request(verb, url, redirects:, headers: {})
      return nil if redirects.negative?

      uri = URI.parse(url)
      return nil unless uri.is_a?(URI::HTTP)

      response = perform(verb, uri, headers)
      return nil unless response

      case response
      when Net::HTTPRedirection
        location = response['location']
        return nil unless location

        request(verb, URI.join(url, location).to_s, redirects: redirects - 1, headers: headers)
      when Net::HTTPSuccess
        Response.new(status: response.code.to_i, headers: normalize(response), body: response.body, url: url)
      end
    end

    def perform(verb, uri, headers)
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == 'https', open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
      ) do |http|
        http.request(verb.new(uri, { 'User-Agent' => USER_AGENT }.merge(headers)))
      end
    rescue StandardError => e
      warn "    http error: #{e.class}: #{e.message}"
      nil
    end

    def normalize(response)
      response.each_header.to_h { |key, value| [key.downcase, value] }
    end
  end
end
