# frozen_string_literal: true

require 'time'

require_relative 'media_resolver'
require_relative 'enclosure'
require_relative 'discovery'
require_relative 'duration'
require_relative 'published_at'

# Turns the interview list into the episodes the feed template renders, and says
# what it left out and why.
#
# The `audio` block in `list.yml` is the source of truth. An entry that records
# only a URL is probed for the MIME type and byte length an `<enclosure>` needs —
# pass a different `probe` to avoid the network.
module FeedBuilder
  Build = Struct.new(:episodes, :skipped, keyword_init: true)

  Skip = Struct.new(:title, :reason, keyword_init: true)

  # What an entry is called in its item description. A section with no label is
  # not published, which is why `books` and `other` never reach the feed.
  LABELS = { 'podcast_interviews' => 'Interview', 'talks' => 'Talk' }.freeze

  # Where an item points and what identifies it, in falling order of who owns the
  # page: an episode is attributed to whoever published it, and Apple and Pocket
  # Casts published none of these. The resolver's order is the other way round,
  # because an aggregator is the better place to ask for the audio.
  #
  # A client tells episodes apart by `guid` alone, so an entry that changes which
  # of these it answers with arrives again as unheard.
  PAGE_URL_KEYS = %w[url youtube_url podcast_url].freeze

  class << self
    # Takes the whole of `list.yml`: any section with a label contributes whatever
    # entries carry audio, so a talk released as a podcast episode is published
    # without needing to be filed as an interview.
    def build(list, probe: Enclosure.method(:probe))
      episodes = []
      skipped = []

      LABELS.each_key do |section|
        (list[section] || []).each do |entry|
          episode, reason = episode_for(entry, section, probe)
          episode ? episodes << episode : skipped << Skip.new(title: entry['title'], reason: reason)
        end
      end

      episodes.sort_by! { |episode| episode[:published_at] }
      episodes.reverse!

      # A conversation listed twice — say, once as the host's video and once as the
      # show's episode — resolves to one file, and a client would offer it twice.
      # Normalized, because the same file is served under a tracking prefix or a
      # `?dest-id=` suffix depending on which listing the entry came from.
      Build.new(episodes: episodes.uniq { |episode| Discovery.normalize_audio_url(episode[:audio_url]) },
                skipped: skipped)
    end

    private

    def episode_for(entry, section, probe)
      audio_url = entry.dig('audio', 'url')
      return [nil, 'no audio url'] unless audio_url

      details = recorded(entry) || probe.call(audio_url)
      # An enclosure without a byte count is rejected by strict clients, so an
      # unreachable file is no more use in the feed than a missing one.
      return [nil, "could not read #{audio_url}"] unless details
      return [nil, "audio length #{details.length} is too small to be an episode"] unless details.usable?

      [episode(entry, section, audio_url, details), nil]
    end

    # A build that trusts the list asks nobody anything. Probing is the fallback
    # for an entry added by hand, and it fails wherever the host blocks CI.
    def recorded(interview)
      audio = interview['audio'] || {}
      type = audio['type']
      length = audio['length']
      return nil unless type && length

      Enclosure::Details.new(type: type, length: length.to_i)
    end

    def episode(entry, section, audio_url, details)
      page_url = PAGE_URL_KEYS.filter_map { |key| entry[key] }.first
      show_name = entry.dig('show', 'name') || 'Unknown Show'

      {
        title: entry['title'],
        page_url: page_url,
        guid: page_url,
        # A talk records when it was delivered; an interview, when it was published.
        # `published_at` is the instant the show's own feed stated, where one was
        # found; the date is what the anthology asserts, and stands otherwise.
        published_at: PublishedAt.parse(
          entry['published_at'] || entry['published_date'] || entry['delivered_date']
        ),
        label: LABELS.fetch(section),
        show_name: show_name,
        show_url: entry.dig('show', 'url'),
        audio_url: audio_url,
        image_url: entry['image_url'] || entry.dig('show', 'image_url'),
        duration: Duration.hms(Duration.seconds(entry.dig('audio', 'duration'))),
        type: details.type,
        length: details.length
      }
    end
  end
end
