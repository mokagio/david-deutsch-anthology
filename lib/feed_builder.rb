# frozen_string_literal: true

require 'time'

require_relative 'audio_resolver'
require_relative 'enclosure'

# Turns the interview list into the episodes the feed template renders, and says
# what it left out and why.
#
# `audio_url` in `list.yml` is the source of truth. The MIME type and byte length
# an `<enclosure>` needs are not recorded there, so they are probed — pass a
# different `probe` to avoid the network.
module FeedBuilder
  Build = Struct.new(:episodes, :skipped, keyword_init: true)

  Skip = Struct.new(:title, :reason, keyword_init: true)

  class << self
    def build(interviews, probe: Enclosure.method(:probe))
      episodes = []
      skipped = []

      interviews.each do |interview|
        episode, reason = episode_for(interview, probe)
        episode ? episodes << episode : skipped << Skip.new(title: interview['title'], reason: reason)
      end

      episodes.sort_by! { |episode| episode[:published_at] }
      episodes.reverse!

      # A conversation listed twice — say, once as the host's video and once as the
      # show's episode — resolves to one file, and a client would offer it twice.
      Build.new(episodes: episodes.uniq { |episode| episode[:audio_url] }, skipped: skipped)
    end

    private

    def episode_for(interview, probe)
      audio_url = interview['audio_url']
      return [nil, 'no audio_url'] unless audio_url

      details = probe.call(audio_url)
      # An enclosure without a byte count is rejected by strict clients, so an
      # unreachable file is no more use in the feed than a missing one.
      return [nil, "could not read #{audio_url}"] unless details&.usable?

      [episode(interview, audio_url, details), nil]
    end

    def episode(interview, audio_url, details)
      source_url = AudioResolver.source_url(interview)
      show_name = interview.dig('show', 'name') || 'Unknown Show'

      {
        title: interview['title'],
        page_url: source_url,
        guid: source_url,
        published_at: Time.parse(interview['published_date']),
        description: "Interview on #{show_name}",
        show_name: show_name,
        audio_url: audio_url,
        type: details.type,
        length: details.length
      }
    end
  end
end
