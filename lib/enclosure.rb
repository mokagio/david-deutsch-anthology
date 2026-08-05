# frozen_string_literal: true

require 'uri'

require_relative 'http_client'

# What an RSS `<enclosure>` needs about an audio file beyond its URL: the MIME
# type and the byte length, neither of which `list.yml` records.
module Enclosure
  Details = Struct.new(:type, :length, keyword_init: true) do
    def usable? = !type.nil? && length.to_i.positive?
  end

  AUDIO_EXTENSIONS = %w[.mp3 .m4a .aac .ogg .oga .opus .wav].freeze

  MIME_TYPES = {
    '.mp3' => 'audio/mpeg', '.m4a' => 'audio/x-m4a', '.aac' => 'audio/aac',
    '.ogg' => 'audio/ogg', '.oga' => 'audio/ogg', '.opus' => 'audio/opus', '.wav' => 'audio/wav'
  }.freeze

  DEFAULT_MIME_TYPE = 'audio/mpeg'

  class << self
    def probe(url)
      response = HttpClient.head(url)
      return nil unless response

      Details.new(
        type: audio_content_type(response.headers['content-type']) || mime_type_for(response.url || url),
        length: response.headers['content-length'].to_i
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
