# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rss'
require 'uri'

require_relative 'http_client'
require_relative 'episode_matcher'
require_relative 'enclosure'

# Turns an interview's human-facing URL into a playable audio file.
#
# Strategies run in order of how trustworthy their answer is: a feed enclosure
# comes with the MIME type and byte length already stated, while a URL scraped
# from a page has to be probed for both and may carry the site's own tracking
# parameters.
class AudioResolver
  APPLE_PODCASTS_URL = %r{podcasts\.apple\.com/.*?/id(?<collection>\d+).*?[?&]i=(?<episode>\d+)}

  Result = Struct.new(:audio_url, :type, :length, :duration, :strategy, :matched_title, :reason,
                      keyword_init: true) do
    def resolved? = !audio_url.nil?
  end

  def initialize(logger: method(:puts))
    @logger = logger
    @pages = {}
    @feeds = {}
    @itunes_searches = {}
  end

  def resolve(interview)
    url = source_url(interview)
    return Result.new(reason: 'entry has no URL') unless url

    %i[direct apple feed page].each do |strategy|
      result = send("resolve_via_#{strategy}", url, interview)
      next unless result&.resolved?

      log "    resolved via #{strategy}: #{result.audio_url}"
      return result
    end

    Result.new(reason: 'no audio source found')
  end

  def self.source_url(interview)
    interview['podcast_url'] || interview['url'] || interview['youtube_url']
  end

  private

  attr_reader :logger

  def source_url(interview) = self.class.source_url(interview)

  def log(message) = logger.call(message)

  # --- strategies ---------------------------------------------------------

  def resolve_via_direct(url, _interview)
    return nil unless audio_url?(url)

    describe(url, strategy: 'direct')
  end

  def resolve_via_apple(url, interview)
    match = APPLE_PODCASTS_URL.match(url)
    return nil unless match

    results = itunes_lookup(match[:collection])
    episode = results.find { |result| result['trackId'].to_s == match[:episode] }

    if episode && episode['episodeUrl']
      return describe(
        episode['episodeUrl'],
        strategy: 'apple',
        type: episode['episodeFileExtension'] ? nil : Enclosure::DEFAULT_MIME_TYPE,
        duration: milliseconds_to_duration(episode['trackTimeMillis'])
      )
    end

    # Apple only hands back the most recent episodes, so older ones have to come
    # out of the show's own feed.
    feed_url = results.find { |result| result['feedUrl'] }&.fetch('feedUrl')
    feed_url ? match_in_feed(feed_url, interview) : nil
  end

  def resolve_via_feed(url, interview)
    feed_urls(url, interview).each do |feed_url|
      result = match_in_feed(feed_url, interview)
      return result if result&.resolved?
    end

    nil
  end

  def resolve_via_page(url, _interview)
    body = page(url)
    return nil unless body

    candidate = open_graph_audio(body) || scraped_audio(body)
    candidate ? describe(candidate, strategy: 'page') : nil
  end

  # --- feed handling ------------------------------------------------------

  def feed_urls(url, interview)
    candidates = []
    candidates << interview.dig('show', 'feed_url')
    candidates.concat(feeds_declared_on_page(url))
    # The show's home page carries the feed link when the entry points at YouTube,
    # and is more reliable than searching iTunes for a show by name.
    candidates.concat(feeds_declared_on_page(interview.dig('show', 'url')))
    candidates.concat(itunes_search_feeds(interview.dig('show', 'name')))
    candidates.compact.uniq
  end

  def feeds_declared_on_page(url)
    return [] if url.nil? || youtube?(url)

    body = page(url)
    return [] unless body

    body.scan(/<link[^>]+>/i)
        .select { |tag| tag.match?(%r{type=["']application/rss\+xml["']}i) }
        .filter_map { |tag| tag[/href=["']([^"']+)["']/i, 1] }
        .map { |href| CGI.unescapeHTML(href) }
        # A WordPress page advertises its comments feed too; those never hold episodes.
        .reject { |href| href.include?('comments') }
        .map { |href| URI.join(url, href).to_s }
  rescue URI::Error
    []
  end

  def match_in_feed(feed_url, interview)
    candidates = feed_candidates(feed_url)
    return nil if candidates.empty?

    match = EpisodeMatcher.best_match(
      candidates,
      title: interview['title'],
      published_on: interview['published_date']
    )
    return nil unless match

    result =
      if match.length.to_i.positive?
        Result.new(
          audio_url: match.audio_url,
          type: match.type || mime_type_for(match.audio_url),
          length: match.length,
          duration: match.duration,
          strategy: 'feed'
        )
      else
        # Some hosts (Megaphone among them) publish `length="0"`, which is a valid
        # feed and an unplayable enclosure in strict clients — ask the file itself.
        describe(match.audio_url, strategy: 'feed', type: match.type, duration: match.duration)
      end

    result.matched_title = match.title
    result
  end

  def feed_candidates(feed_url)
    @feeds[feed_url] ||= begin
      log "    reading feed #{feed_url}"
      response = HttpClient.get(feed_url)
      response ? parse_feed(response.body) : []
    end
  end

  def parse_feed(body)
    feed = RSS::Parser.parse(body, false)
    return [] unless feed

    feed.items.filter_map do |item|
      enclosure = item.respond_to?(:enclosure) ? item.enclosure : nil
      next unless enclosure&.url

      EpisodeMatcher::Candidate.new(
        title: item_title(item),
        published_on: item_date(item),
        audio_url: enclosure.url,
        type: enclosure.type,
        length: enclosure.length&.to_i,
        duration: item_duration(item)
      )
    end
  rescue StandardError => e
    warn "    feed parse error: #{e.class}: #{e.message}"
    []
  end

  def item_title(item)
    title = item.title
    title.respond_to?(:content) ? title.content : title
  end

  def item_date(item)
    item.respond_to?(:pubDate) ? item.pubDate : nil
  rescue StandardError
    nil
  end

  def item_duration(item)
    item.itunes_duration&.content if item.respond_to?(:itunes_duration)
  rescue StandardError
    nil
  end

  # --- iTunes -------------------------------------------------------------

  def itunes_lookup(collection_id)
    @itunes_searches[collection_id] ||= itunes_get(
      "https://itunes.apple.com/lookup?id=#{collection_id}&entity=podcastEpisode&limit=200"
    )
  end

  def itunes_search_feeds(show_name)
    return [] unless show_name

    @itunes_searches[show_name] ||= itunes_get(
      "https://itunes.apple.com/search?term=#{CGI.escape(show_name)}&entity=podcast&limit=3"
    )
    @itunes_searches[show_name].filter_map { |result| result['feedUrl'] }
  end

  def itunes_get(url)
    response = HttpClient.get(url)
    return [] unless response

    JSON.parse(response.body)['results'] || []
  rescue JSON::ParserError
    []
  end

  # --- page scraping ------------------------------------------------------

  def page(url)
    return nil if youtube?(url)

    @pages[url] ||= begin
      log "    fetching #{url}"
      HttpClient.get(url)&.body || :none
    end
    @pages[url] == :none ? nil : @pages[url]
  end

  def open_graph_audio(body)
    tag = body.scan(/<meta[^>]+>/i).find do |meta|
      meta.match?(/property=["']og:audio(:secure_url)?["']/i) && meta.match?(/content=/i)
    end
    return nil unless tag

    url = CGI.unescapeHTML(tag[/content=["']([^"']+)["']/i, 1].to_s)
    audio_url?(url) ? url : nil
  end

  def scraped_audio(body)
    body.scan(%r{https?://[^"'\s<>\\)]+?\.(?:mp3|m4a)(?:\?[^"'\s<>\\)]*)?}i)
        .map { |url| CGI.unescapeHTML(url) }
        .uniq
        .min_by(&:length)
  end

  # --- helpers ------------------------------------------------------------

  def describe(url, strategy:, type: nil, duration: nil)
    details = Enclosure.probe(url)

    Result.new(
      audio_url: url,
      type: type || details&.type || Enclosure.mime_type_for(url),
      length: details&.length,
      duration: duration,
      strategy: strategy
    )
  end

  def audio_url?(url) = Enclosure.audio_url?(url)

  def mime_type_for(url) = Enclosure.mime_type_for(url)

  def milliseconds_to_duration(milliseconds)
    return nil unless milliseconds

    seconds = milliseconds / 1000
    format('%02d:%02d:%02d', seconds / 3600, (seconds % 3600) / 60, seconds % 60)
  end

  def youtube?(url) = url.include?('youtube.com') || url.include?('youtu.be')
end
