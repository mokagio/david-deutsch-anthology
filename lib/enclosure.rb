# frozen_string_literal: true

require 'uri'

require_relative 'http_client'

# What an RSS `<enclosure>` needs about an audio file beyond its URL: the MIME
# type and the byte length, neither of which `list.yml` records.
module Enclosure
  # A podcast episode is never a few kilobytes. Hosts that answer a size request
  # with a stub — acast returns two bytes of `text/plain` — otherwise sail through
  # a positive-number check and publish an enclosure no client can play.
  MIN_PLAUSIBLE_BYTES = 100_000

  Details = Struct.new(:type, :length, keyword_init: true) do
    def usable? = !type.nil? && length.to_i >= Enclosure::MIN_PLAUSIBLE_BYTES
  end

  AUDIO_EXTENSIONS = %w[.mp3 .m4a .aac .ogg .oga .opus .wav].freeze

  MIME_TYPES = {
    '.mp3' => 'audio/mpeg', '.m4a' => 'audio/x-m4a', '.aac' => 'audio/aac',
    '.ogg' => 'audio/ogg', '.oga' => 'audio/ogg', '.opus' => 'audio/opus', '.wav' => 'audio/wav'
  }.freeze

  DEFAULT_MIME_TYPE = 'audio/mpeg'

  class << self
    def probe(url)
      head = HttpClient.head(url)
      head_type = audio_content_type(head&.headers&.dig('content-type'))
      head_length = head&.headers&.dig('content-length').to_i

      # A HEAD that does not describe audio is a stub whatever length it claims —
      # acast answers with two bytes of `text/plain`. Only the range request's
      # Content-Range can be believed.
      return Details.new(type: head_type, length: head_length) if head_type && head_length.positive?

      ranged = HttpClient.ranged_get(url)
      total = ranged&.headers&.dig('content-range')&.slice(%r{/(\d+)\z}, 1)
      return nil unless total

      Details.new(
        type: audio_content_type(ranged.headers['content-type']) || head_type || mime_type_for(ranged.url || url),
        length: total.to_i
      )
    end

    def audio_url?(url) = AUDIO_EXTENSIONS.include?(extension(url))

    def mime_type_for(url) = MIME_TYPES.fetch(extension(url), DEFAULT_MIME_TYPE)

    def extension(url)
      File.extname(URI.parse(url).path.to_s).downcase
    rescue URI::Error
      ''
    end

    private

    def audio_content_type(header)
      type = header&.split(';')&.first
      type if type&.start_with?('audio/')
    end
  end
end
