# frozen_string_literal: true

require 'time'

require_relative 'audio_resolver'

# Turns the interview list plus the audio dictionary into the episodes the feed
# template renders, and says what it left out and why.
module FeedBuilder
  Build = Struct.new(:episodes, :skipped, keyword_init: true)

  Skip = Struct.new(:title, :reason, keyword_init: true)

  class << self
    def build(interviews, dictionary)
      episodes = []
      skipped = []

      interviews.each do |interview|
        reason = unusable_reason(dictionary[AudioResolver.source_url(interview)])

        if reason
          skipped << Skip.new(title: interview['title'], reason: reason)
        else
          episodes << episode(interview, dictionary[AudioResolver.source_url(interview)])
        end
      end

      episodes.sort_by! { |episode| episode[:published_at] }
      episodes.reverse!

      # A conversation listed twice — say, once as the host's video and once as the
      # show's episode — resolves to one file, and a client would offer it twice.
      Build.new(episodes: episodes.uniq { |episode| episode[:audio_url] }, skipped: skipped)
    end

    private

    def unusable_reason(entry)
      return 'not resolved yet' unless entry
      return entry['reason'] || 'no audio source found' unless entry['audio_url']
      # An enclosure without a byte count is rejected by strict clients, so such an
      # entry is no more use in the feed than one with no audio at all.
      return 'audio file size unknown' unless entry['length'].to_i.positive?

      nil
    end

    def episode(interview, entry)
      source_url = AudioResolver.source_url(interview)
      show_name = interview.dig('show', 'name') || 'Unknown Show'

      {
        title: interview['title'],
        page_url: source_url,
        guid: source_url,
        published_at: Time.parse(interview['published_date']),
        description: "Interview on #{show_name}",
        show_name: show_name,
        audio_url: entry['audio_url'],
        type: entry['type'] || 'audio/mpeg',
        length: entry['length'].to_i,
        duration: entry['duration']
      }
    end
  end
end
