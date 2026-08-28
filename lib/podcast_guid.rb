# frozen_string_literal: true

require 'digest/sha1'

# What identifies this podcast to a client, as against what identifies an
# episode. Assigned once and carried for the feed's lifetime, so moving the feed
# to another URL does not present the show as a new one.
#
# It is a UUIDv5 over the feed URL rather than the URL itself, in the namespace
# the podcast namespace reserves for the purpose, seeded with the URL stripped of
# its scheme and any trailing slash.
# https://podcastindex.org/namespace/1.0#guid
module PodcastGuid
  NAMESPACE = 'ead4c236-bf58-58c6-a2c6-a6b28d128cb6'

  class << self
    def for(feed_url) = uuid_v5(NAMESPACE, seed(feed_url))

    private

    def seed(feed_url) = feed_url.to_s.strip.sub(%r{\Ahttps?://}, '').sub(%r{/+\z}, '')

    def uuid_v5(namespace, name)
      bytes = Digest::SHA1.digest([namespace.delete('-')].pack('H*') + name).bytes.first(16)
      bytes[6] = (bytes[6] & 0x0F) | 0x50 # version 5
      bytes[8] = (bytes[8] & 0x3F) | 0x80 # RFC 4122 variant
      hex = bytes.map { |byte| Kernel.format('%02x', byte) }.join
      [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')
    end
  end
end
