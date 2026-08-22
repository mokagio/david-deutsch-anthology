# frozen_string_literal: true

require 'date'
require 'uri'

require_relative 'episode_matcher'

# Decides whether an appearance found in the wild is one `list.yml` already holds.
#
# A sweep returns the same conversation under several names — the show's own page,
# its Apple listing, a YouTube upload, the mp3 behind all three — so "is this URL
# in the list" answers only the easiest case. Three tests run in falling order of
# confidence: the URL, the audio file, then the wording and the date.
#
# The asymmetry that shapes every threshold here: a duplicate reported as new
# costs one glance, while a genuinely new appearance suppressed as a duplicate is
# never seen again. When in doubt, report it.
module Discovery
  Candidate = Struct.new(:title, :url, :audio_url, :published_on, :show_name, :source, :image_url,
                         :duration, keyword_init: true)

  # Wording alone settles it only when it is near-identical; below that it needs
  # the show or the date to agree.
  CERTAIN_TITLE_SIMILARITY = 0.85
  CORROBORATED_TITLE_SIMILARITY = 0.6

  # Shows publish audio and video a day or two apart, and the list records a talk
  # by the date it was delivered rather than the date a feed carried it.
  MAX_DATE_DISTANCE_DAYS = 7

  # Query parameters that identify the visitor rather than the page.
  TRACKING_PARAMS = %w[utm_source utm_medium utm_campaign utm_term utm_content si ref ref_src
                       fbclid gclid t feature ab_channel pp].freeze

  YOUTUBE_HOSTS = %w[youtube.com youtu.be m.youtube.com music.youtube.com].freeze

  # Every URL an entry can be reached by. `show.url` is deliberately absent: a
  # candidate sitting at a show's home page is not an episode we already have.
  ENTRY_URL_KEYS = %w[url podcast_url youtube_url].freeze

  DATE_KEYS = %w[published_date delivered_date date].freeze

  class << self
    # Splits candidates into the ones worth looking at and the ones already recorded.
    def sift(candidates, index)
      novel = []
      known = []

      candidates.each do |candidate|
        match = index.seen(candidate)
        match ? known << [candidate, match] : novel << candidate
      end

      [novel, known]
    end

    def normalize_url(url)
      uri = parse(url)
      return nil unless uri

      video = youtube_video_id(uri)
      return "youtube:#{video}" if video

      host = uri.host.to_s.downcase.sub(/\Awww\./, '')
      path = uri.path.to_s.sub(%r{/\z}, '')
      "#{host}#{path}#{normalize_query(uri.query)}"
    end

    # The last two path segments rather than the whole URL: an mp3 is routinely
    # served through a prefix that measures downloads
    # (`chrt.fm/track/XXXX/traffic.libsyn.com/naval/ep.mp3`), and the segments the
    # prefix cannot change are what identify the file. Two are needed because a
    # basename alone is often generic — every TED episode's file is `media.mp3`.
    def normalize_audio_url(url)
      uri = parse(url)
      return nil unless uri

      segments = uri.path.to_s.split('/').reject(&:empty?)
      return nil if segments.empty?

      segments.last(2).join('/').downcase
    end

    def youtube_video_id(uri)
      host = uri.host.to_s.downcase.sub(/\Awww\./, '')
      return nil unless YOUTUBE_HOSTS.include?(host)

      return uri.path.delete_prefix('/').split('/').first if host == 'youtu.be'

      case uri.path
      when '/watch' then URI.decode_www_form(uri.query.to_s).to_h['v']
      when %r{\A/(?:embed|shorts|live|v)/([\w-]+)} then Regexp.last_match(1)
      end
    end

    def entry_date(entry)
      DATE_KEYS.filter_map { |key| entry[key] }.first
    end

    # Case, punctuation and the difference between ' and ’ are never what makes
    # two titles different.
    def fold(text) = text.to_s.downcase.gsub(/[^a-z0-9]+/, ' ').strip

    def entry_urls(entry)
      ENTRY_URL_KEYS.filter_map { |key| entry[key] } +
        (entry['urls'] || []).filter_map { |link| link['url'] }
    end

    private

    def parse(url)
      uri = URI.parse(url.to_s.strip)
      uri.is_a?(URI::HTTP) && uri.host ? uri : nil
    rescue URI::Error
      nil
    end

    def normalize_query(query)
      pairs = URI.decode_www_form(query.to_s).reject { |key, _| TRACKING_PARAMS.include?(key.downcase) }
      pairs.empty? ? '' : "?#{pairs.sort.map { |key, value| "#{key}=#{value}" }.join('&')}"
    end
  end

  # Judgements an earlier run already made, so a sweep does not ask for them again:
  # shows that belong to a namesake, and titles that are commentary on the books
  # rather than an appearance.
  class Ignore
    def initialize(rules)
      rules ||= {}
      @shows = (rules['shows'] || []).to_h { |show| [Discovery.fold(show['name']), show['reason']] }
      @titles = (rules['titles'] || []).map { |title| Discovery.fold(title) }
    end

    # Why this candidate is not worth reporting, or nil.
    def reject(candidate)
      show = Discovery.fold(candidate.show_name)
      return "ignored show: #{@shows[show] || show}" if @shows.key?(show) && !show.empty?

      folded = Discovery.fold(candidate.title)
      pattern = @titles.find { |title| folded.include?(title) }
      pattern ? "ignored title: #{pattern.inspect}" : nil
    end

    def empty? = @shows.empty? && @titles.empty?
  end

  # Everything `list.yml` already knows, in the three shapes a candidate can be
  # recognised by.
  class Index
    Entry = Struct.new(:title, :published_on, :show_name, keyword_init: true)

    def initialize(list)
      @urls = {}
      @audio = {}
      @entries = []

      list.each_value do |entries|
        next unless entries.is_a?(Array)

        entries.each { |entry| index(entry) if entry.is_a?(Hash) }
      end
    end

    attr_reader :entries

    # The entry this candidate already is, and why — or nil when it is new.
    def seen(candidate)
      by_url(candidate) || by_audio(candidate) || by_wording(candidate)
    end

    def size = @entries.size

    private

    def index(entry)
      title = entry['title'] || entry['name']

      Discovery.entry_urls(entry).each do |url|
        key = Discovery.normalize_url(url)
        @urls[key] ||= title if key
      end

      audio_key = Discovery.normalize_audio_url(entry.dig('audio', 'url'))
      @audio[audio_key] ||= title if audio_key

      return unless title

      @entries << Entry.new(
        title: title,
        published_on: Discovery.entry_date(entry),
        show_name: entry.dig('show', 'name')
      )
    end

    def by_url(candidate)
      [candidate.url, candidate.audio_url].each do |url|
        key = Discovery.normalize_url(url)
        title = key && @urls[key]
        return "already listed as #{title.inspect}" if title
      end
      nil
    end

    def by_audio(candidate)
      key = Discovery.normalize_audio_url(candidate.audio_url)
      title = key && @audio[key]
      title ? "same audio file as #{title.inspect}" : nil
    end

    def by_wording(candidate)
      @entries.each do |entry|
        similarity = EpisodeMatcher.title_similarity(candidate.title, entry.title)
        next unless duplicate?(candidate, entry, similarity)

        return format('title matches %<title>s (%<similarity>.2f)', title: entry.title.inspect, similarity: similarity)
      end
      nil
    end

    def duplicate?(candidate, entry, similarity)
      return true if similarity >= Discovery::CERTAIN_TITLE_SIMILARITY
      return false if similarity < Discovery::CORROBORATED_TITLE_SIMILARITY

      same_show?(candidate.show_name, entry.show_name) || close_in_time?(candidate.published_on, entry.published_on)
    end

    def same_show?(one, other)
      left = normalize_show(one)
      right = normalize_show(other)
      return false if left.empty? || right.empty?

      left.include?(right) || right.include?(left)
    end

    def normalize_show(name) = name.to_s.downcase.gsub(/[^a-z0-9]/, '')

    def close_in_time?(one, other)
      distance = EpisodeMatcher.date_distance(one, other)
      !distance.nil? && distance <= Discovery::MAX_DATE_DISTANCE_DAYS
    rescue ArgumentError, TypeError
      false
    end
  end
end
