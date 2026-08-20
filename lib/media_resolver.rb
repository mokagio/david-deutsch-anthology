# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rss'
require 'uri'

require_relative 'http_client'
require_relative 'episode_matcher'
require_relative 'enclosure'
require_relative 'image_probe'

# Turns an interview's human-facing URL into the media a feed item needs: a
# playable audio file, and the picture a client shows beside it.
#
# Strategies run in order of how trustworthy their answer is: a feed enclosure
# comes with the MIME type and byte length already stated, while a URL scraped
# from a page has to be probed for both and may carry the site's own tracking
# parameters.
class MediaResolver
  APPLE_PODCASTS_URL = %r{podcasts\.apple\.com/.*?/id(?<collection>\d+).*?[?&]i=(?<episode>\d+)}

  Result = Struct.new(:audio_url, :type, :length, :duration, :strategy, :matched_title, :reason,
                      keyword_init: true) do
    def resolved? = !audio_url.nil?
  end

  # `scope` says whose picture this is: the episode's own, or the show's, which
  # every episode of that show would get.
  Artwork = Struct.new(:image_url, :scope, :size, :strategy, :matched_title, :reason, keyword_init: true) do
    def found? = !image_url.nil?
  end

  Feed = Struct.new(:candidates, :image_url, keyword_init: true)

  def initialize(logger: method(:puts), image_probe: ImageProbe.method(:details))
    @logger = logger
    @image_probe = image_probe
    @pages = {}
    @feeds = {}
    @feed_matches = {}
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

  # The episode's own picture wherever one exists, whatever it takes to find it;
  # the show's only once every episode-scoped source has come up empty.
  def resolve_artwork(interview)
    url = source_url(interview)
    return Artwork.new(reason: 'entry has no URL') unless url

    artwork = first_artwork(%i[feed_item apple_episode page], url, interview) ||
              first_artwork(%i[feed_channel apple_collection], url, interview)
    return Artwork.new(reason: 'no artwork found') unless artwork

    log "    artwork via #{artwork.strategy}: #{artwork.image_url}"
    artwork
  end

  def self.source_url(interview)
    interview['podcast_url'] || interview['url'] || interview['youtube_url']
  end

  private

  attr_reader :logger

  def source_url(interview) = self.class.source_url(interview)

  def log(message) = logger.call(message)

  # --- audio strategies ---------------------------------------------------

  def resolve_via_direct(url, _interview)
    return nil unless audio_url?(url)

    describe(url, strategy: 'direct')
  end

  def resolve_via_apple(url, interview)
    episode = apple_episode(url)

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
    feed_url = apple_feed_url(url)
    feed_url ? audio_from_feed(feed_url, interview) : nil
  end

  def resolve_via_feed(url, interview)
    feed_url, match = feed_match(url, interview)
    match ? audio_from(feed_url, match) : nil
  end

  def resolve_via_page(url, _interview)
    body = page(url)
    return nil unless body

    candidate = open_graph_audio(body) || scraped_audio(body)
    candidate ? describe(candidate, strategy: 'page') : nil
  end

  # --- artwork strategies -------------------------------------------------

  def first_artwork(strategies, url, interview)
    strategies.lazy.filter_map { |strategy| send("artwork_via_#{strategy}", url, interview) }.first
  end

  def artwork_via_feed_item(url, interview)
    _feed_url, match = feed_match(url, interview)
    return nil unless match&.image_url

    artwork(match.image_url, scope: :episode, strategy: 'feed item', matched_title: match.title)
  end

  # Apple answers with the show's logo for an episode that has no picture of its
  # own, so an artwork that matches the collection's is the show's, not this
  # episode's, whatever the episode record says.
  def artwork_via_apple_episode(url, _interview)
    episode = apple_episode(url)
    image_url = episode&.fetch('artworkUrl600', nil)
    return nil if image_url.nil? || image_url == apple_collection_artwork(url)

    artwork(image_url, scope: :episode, strategy: 'apple')
  end

  def artwork_via_page(url, _interview)
    body = page(url)
    return nil unless body

    image_url = open_graph_image(body)
    image_url ? artwork(image_url, scope: :episode, strategy: 'page') : nil
  end

  def artwork_via_feed_channel(url, interview)
    matched_feed_url, = feed_match(url, interview)

    ([matched_feed_url] + trusted_feed_urls(url, interview)).compact.uniq.lazy.filter_map do |feed_url|
      image_url = read_feed(feed_url).image_url
      image_url && artwork(image_url, scope: :show, strategy: 'feed channel')
    end.first
  end

  # A feed an episode was matched in is this show's beyond doubt; short of that,
  # only a feed the entry or the show names. An iTunes search by show name lands
  # on the wrong show often enough that its logo cannot be trusted unchecked.
  def trusted_feed_urls(url, interview)
    ([interview.dig('show', 'feed_url'), apple_feed_url(url)] +
      feeds_declared_on_page(interview.dig('show', 'url'))).compact.uniq
  end

  def artwork_via_apple_collection(url, _interview)
    image_url = apple_collection_artwork(url)
    image_url ? artwork(image_url, scope: :show, strategy: 'apple collection') : nil
  end

  # A page's `og:image` is as often a banner crop or a favicon as it is the
  # episode's cover, and a client renders whatever it is handed in a square tile.
  def artwork(url, scope:, strategy:, matched_title: nil)
    return nil unless http_url?(url)

    size = @image_probe.call(url)
    return nil if size && !size.artwork?

    Artwork.new(image_url: url, scope: scope, size: size&.to_s, strategy: strategy, matched_title: matched_title)
  end

  # --- feed handling ------------------------------------------------------

  def feed_urls(url, interview)
    candidates = []
    candidates << interview.dig('show', 'feed_url')
    candidates << apple_feed_url(url)
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

  # The feed item this entry is, and the feed it came from. Memoized because both
  # the audio and the artwork want it, and matching means reading every feed the
  # show might publish under.
  def feed_match(url, interview)
    @feed_matches.fetch([url, interview['title']]) do
      @feed_matches[[url, interview['title']]] =
        feed_urls(url, interview).lazy.map { |feed_url| [feed_url, best_candidate(feed_url, interview)] }
                                 .find { |_feed_url, candidate| candidate } || [nil, nil]
    end
  end

  def best_candidate(feed_url, interview)
    candidates = read_feed(feed_url).candidates
    return nil if candidates.empty?

    EpisodeMatcher.best_match(
      candidates,
      title: interview['title'],
      published_on: interview['published_date']
    )
  end

  def audio_from_feed(feed_url, interview)
    match = best_candidate(feed_url, interview)
    match ? audio_from(feed_url, match) : nil
  end

  def audio_from(_feed_url, match)
    # Always ask the file rather than believe the feed: Megaphone publishes
    # `length="0"`, and The TED Interview's feed overstates by 43%. The declared
    # value is only a fallback for a file that will not answer.
    result = describe(match.audio_url, strategy: 'feed', type: match.type, duration: match.duration)
    result.length = match.length if result.length.to_i < Enclosure::MIN_PLAUSIBLE_BYTES

    result.matched_title = match.title
    result
  end

  def read_feed(feed_url)
    @feeds[feed_url] ||= begin
      log "    reading feed #{feed_url}"
      response = HttpClient.get(feed_url)
      response ? parse_feed(response.body) : Feed.new(candidates: [], image_url: nil)
    end
  end

  def parse_feed(body)
    feed = RSS::Parser.parse(body, false)
    return Feed.new(candidates: [], image_url: nil) unless feed

    candidates = feed.items.filter_map do |item|
      enclosure = item.respond_to?(:enclosure) ? item.enclosure : nil
      next unless enclosure&.url

      EpisodeMatcher::Candidate.new(
        title: item_title(item),
        published_on: item_date(item),
        audio_url: enclosure.url,
        type: enclosure.type,
        length: enclosure.length&.to_i,
        duration: item_duration(item),
        image_url: item_image(item)
      )
    end

    Feed.new(candidates: candidates, image_url: channel_image(feed))
  rescue StandardError => e
    warn "    feed parse error: #{e.class}: #{e.message}"
    Feed.new(candidates: [], image_url: nil)
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

  def item_image(item)
    item.itunes_image&.href if item.respond_to?(:itunes_image)
  rescue StandardError
    nil
  end

  # `<itunes:image>` is what a client shows; RSS 2.0's own `<image>` is a 144px
  # thumbnail for a web page, and only worth reading when there is nothing else.
  def channel_image(feed)
    channel = feed.channel
    (channel.itunes_image&.href if channel.respond_to?(:itunes_image)) || channel.image&.url
  rescue StandardError
    nil
  end

  # --- iTunes -------------------------------------------------------------

  def apple_results(url)
    match = APPLE_PODCASTS_URL.match(url)
    match ? itunes_lookup(match[:collection]) : []
  end

  def apple_episode(url)
    match = APPLE_PODCASTS_URL.match(url)
    return nil unless match

    itunes_lookup(match[:collection]).find { |result| result['trackId'].to_s == match[:episode] }
  end

  def apple_collection(url)
    apple_results(url).find { |result| result['wrapperType'] != 'podcastEpisode' }
  end

  def apple_collection_artwork(url) = apple_collection(url)&.fetch('artworkUrl600', nil)

  def apple_feed_url(url) = apple_results(url).find { |result| result['feedUrl'] }&.fetch('feedUrl')

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
    url = open_graph_content(body, 'audio')
    url && audio_url?(url) ? url : nil
  end

  def open_graph_image(body) = open_graph_content(body, 'image')

  def open_graph_content(body, property)
    tag = body.scan(/<meta[^>]+>/i).find do |meta|
      meta.match?(/property=["']og:#{property}(:secure_url)?["']/i) && meta.match?(/content=/i)
    end
    return nil unless tag

    CGI.unescapeHTML(tag[/content=["']([^"']+)["']/i, 1].to_s)
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

  def http_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTP) && !uri.host.nil?
  rescue URI::Error
    false
  end

  def milliseconds_to_duration(milliseconds)
    return nil unless milliseconds

    seconds = milliseconds / 1000
    format('%02d:%02d:%02d', seconds / 3600, (seconds % 3600) / 60, seconds % 60)
  end

  def youtube?(url) = url.include?('youtube.com') || url.include?('youtu.be')
end
