# frozen_string_literal: true

require 'rss'
require 'time'
require 'uri'

require_relative 'enclosure'

# Checks the generated feed against what a podcast client needs, which is a
# stricter bar than "valid RSS": an item with no enclosure parses fine and then
# shows up in no app.
module FeedValidator
  REQUIRED_CHANNEL_FIELDS = %w[title link description].freeze

  class << self
    def errors(xml)
      feed = begin
        RSS::Parser.parse(xml, true)
      rescue RSS::InvalidRSSError, RSS::NotWellFormedError => e
        return ["feed does not parse as RSS 2.0: #{e.message}"]
      end

      return ['feed does not parse as RSS 2.0'] unless feed

      channel_errors(feed.channel) + item_errors(feed.items)
    end

    private

    def channel_errors(channel)
      errors = REQUIRED_CHANNEL_FIELDS.reject { |field| present?(channel.public_send(field)) }
                                      .map { |field| "channel is missing <#{field}>" }
      errors << 'channel has no items' if channel.items.empty?
      errors
    end

    def item_errors(items)
      items.flat_map do |item|
        label = item.title || item.link || '(untitled item)'
        enclosure_errors(item, label) + metadata_errors(item, label)
      end
    end

    def enclosure_errors(item, label)
      enclosure = item.enclosure
      return ["#{label}: no <enclosure>, so no client can play it"] unless enclosure

      errors = []
      errors << "#{label}: enclosure url is not an absolute http(s) URL" unless http_url?(enclosure.url)
      errors << "#{label}: enclosure type #{enclosure.type.inspect} is not an audio type" unless audio?(enclosure.type)
      unless enclosure.length.to_i >= Enclosure::MIN_PLAUSIBLE_BYTES
        errors << "#{label}: enclosure length #{enclosure.length} is too small to be an episode"
      end
      errors
    end

    def metadata_errors(item, label)
      errors = []
      errors << "#{label}: missing <title>" unless present?(item.title)
      errors << "#{label}: missing <guid>" unless present?(item.guid&.content)
      errors << "#{label}: missing or unparseable <pubDate>" unless item.pubDate
      errors
    end

    def present?(value) = !value.nil? && !value.to_s.strip.empty?

    def audio?(type) = type.to_s.start_with?('audio/')

    def http_url?(url)
      uri = URI.parse(url.to_s)
      uri.is_a?(URI::HTTP) && !uri.host.nil?
    rescue URI::Error
      false
    end
  end
end
