# frozen_string_literal: true

# Looks for David Deutsch appearances that `list.yml` does not have yet.
#
# Three sweeps, each cheap and each blind to what the others see: Apple's episode
# index, the feed of every show already in the list, and the YouTube channels the
# list names. What comes back is sifted against the list and reported; nothing is
# written.
#
#   ruby .claude/skills/find-entries/scripts/find_entries.rb [--source itunes,spotify,feeds]
#                                                            [--since YYYY-MM-DD] [--feed URL]
#                                                            [--own-channel] [--json] [--all]

require 'cgi/escape'
require 'date'
require 'json'
require 'rss'
require 'set'
require 'uri'
require 'yaml'

ROOT = File.expand_path('../../../..', __dir__)
require File.join(ROOT, 'lib', 'http_client')
require File.join(ROOT, 'lib', 'episode_matcher')
require File.join(ROOT, 'lib', 'spotify')
require File.join(ROOT, 'lib', 'discovery')

# Reads any feed a sweep lands on — a show's RSS or a YouTube channel's Atom —
# into the one shape the sifter understands.
module FeedReader
  class << self
    def candidates(feed_url, show_name:, source:)
      body = HttpClient.get(feed_url)&.body
      return [] unless body

      feed = RSS::Parser.parse(body, false)
      return [] unless feed

      feed.items.filter_map { |item| candidate(item, show_name: show_name || channel_title(feed), source: source) }
    rescue StandardError => e
      warn "    feed error #{feed_url}: #{e.class}: #{e.message}"
      []
    end

    private

    def candidate(item, show_name:, source:)
      title = text(item.title)
      return nil if title.to_s.empty?

      enclosure = item.respond_to?(:enclosure) ? item.enclosure : nil

      Discovery::Candidate.new(
        title: title,
        url: link(item),
        audio_url: enclosure&.url,
        published_on: published_on(item),
        show_name: show_name,
        source: source,
        image_url: (item.itunes_image&.href if item.respond_to?(:itunes_image)),
        duration: (item.itunes_duration&.content if item.respond_to?(:itunes_duration))
      )
    rescue StandardError
      nil
    end

    # RSS 2.0 hands back the URL as a string; Atom wraps it in a link element.
    def link(item)
      value = item.link
      value.respond_to?(:href) ? value.href : value
    end

    def published_on(item)
      %i[pubDate published updated].each do |method|
        next unless item.respond_to?(method)

        value = item.public_send(method)
        value = value.content if value.respond_to?(:content)
        return value if value
      end
      nil
    end

    def channel_title(feed)
      channel = feed.respond_to?(:channel) ? feed.channel : feed
      text(channel.title)
    rescue StandardError
      nil
    end

    def text(value) = value.respond_to?(:content) ? value.content : value
  end
end

# Works out where a show publishes, from whatever the list records about it.
class FeedFinder
  YOUTUBE_HOST = /(?:\A|\.)youtube\.com\z|\Ayoutu\.be\z/

  def initialize
    @channel_ids = {}
    @itunes = {}
  end

  # Returns [feed_url, kind] where kind is :rss or :youtube, or nil when the show
  # cannot be located — which the report names, so a silent hole in the sweep does
  # not read as "nothing new on that show".
  def find(name:, url:, feed_url: nil)
    return [feed_url, :rss] if feed_url

    if youtube?(url)
      channel = youtube_channel_feed(url)
      return channel ? [channel, :youtube] : nil
    end

    declared = declared_feed(url) || itunes_feed(name)
    declared ? [declared, :rss] : nil
  end

  def youtube?(url)
    host = URI.parse(url.to_s).host
    !host.nil? && host.sub(/\Awww\./, '').match?(YOUTUBE_HOST)
  rescue URI::Error
    false
  end

  # Every YouTube URL the list carries — a handle, a channel id, a video, a
  # playlist — serves a page that leads back to the channel's feed.
  def youtube_channel_feed(url)
    @channel_ids.fetch(url) { @channel_ids[url] = resolve_youtube_feed(url) }
  end

  private

  def resolve_youtube_feed(url)
    id = url[%r{/channel/(UC[\w-]+)}, 1]
    return feed_for(id) if id

    body = HttpClient.get(url)&.body
    return nil unless body

    # A channel page links its own feed; a watch page does not, and names the
    # channel under one of three keys depending on which page YouTube served.
    body[%r{href="(https://www\.youtube\.com/feeds/videos\.xml\?channel_id=UC[\w-]+)"}, 1] ||
      feed_for(body[/"(?:externalId|browseId|channelId)":"(UC[\w-]+)"/, 1])
  end

  def feed_for(id) = id && "https://www.youtube.com/feeds/videos.xml?channel_id=#{id}"

  def declared_feed(url)
    return nil if url.nil? || !url.start_with?('http')

    body = HttpClient.get(url)&.body
    return nil unless body

    body.scan(/<link[^>]+>/i)
        .select { |tag| tag.match?(%r{type=["']application/(?:rss|atom)\+xml["']}i) }
        .filter_map { |tag| tag[/href=["']([^"']+)["']/i, 1] }
        .map { |href| CGI.unescapeHTML(href) }
        .reject { |href| href.include?('comments') }
        .filter_map { |href| absolute(href, url) }
        .first
  end

  def absolute(href, base)
    URI.join(base, href).to_s
  rescue URI::Error
    nil
  end

  # Searching Apple by show name lands on the wrong show often enough that the
  # name it answers with has to agree before its feed is swept.
  def itunes_feed(name)
    return nil unless name

    results = @itunes[name] ||= itunes("search?term=#{CGI.escape(name)}&entity=podcast&limit=5")
    match = results.find { |result| EpisodeMatcher.title_similarity(result['collectionName'], name) >= 0.6 }
    match&.fetch('feedUrl', nil)
  end

  def itunes(query)
    response = HttpClient.get("https://itunes.apple.com/#{query}")
    response ? JSON.parse(response.body)['results'] || [] : []
  rescue JSON::ParserError
    []
  end
end

# Apple's index reaches shows the list has never heard of, which is the only sweep
# here that can find an appearance on a show he has not been on before.
module ItunesSweep
  TERMS = ['david deutsch', 'david deutsch interview', 'constructor theory', 'beginning of infinity'].freeze

  def self.candidates(logger)
    TERMS.flat_map do |term|
      logger.call("  searching Apple for #{term.inspect}")
      results(term).map do |result|
        Discovery::Candidate.new(
          title: result['trackName'],
          url: result['trackViewUrl'],
          audio_url: result['episodeUrl'],
          published_on: result['releaseDate'],
          show_name: result['collectionName'],
          source: 'apple',
          image_url: result['artworkUrl600'],
          duration: result['trackTimeMillis'] && (result['trackTimeMillis'] / 1000)
        )
      end
    end
  end

  def self.results(term)
    url = "https://itunes.apple.com/search?term=#{CGI.escape(term)}&entity=podcastEpisode&limit=200"
    response = HttpClient.get(url)
    response ? JSON.parse(response.body)['results'] || [] : []
  rescue JSON::ParserError
    []
  end
end

# Spotify indexes shows that publish nowhere else, and the only way to read one is
# to ask it. What comes back is a lead, never audio: see `Spotify`.
module SpotifySweep
  TERMS = ['david deutsch', 'david deutsch interview', 'constructor theory'].freeze

  class << self
    # Search hands back an episode with no sign of what show it is from, and the
    # endpoint that would read fifty of them back whole is forbidden to an
    # application's own credentials. So the name filter runs first, on the title
    # alone, and only what survives it is read back one at a time.
    def search(client, logger, &keep)
      wanted = {}

      TERMS.each do |term|
        logger.call("  searching Spotify for #{term.inspect}")
        client.search_episodes(term).each do |episode|
          found = candidate(episode)
          wanted[episode['id']] ||= found if keep.call(found)
        end
      end

      wanted.map { |id, found| name_show(client, id, found) }
    end

    def name_show(client, id, candidate)
      candidate.show_name = client.episode(id)&.dig('show', 'name')
      candidate
    end

    def show(client, show_id) = client.show_episodes(show_id).map { |episode| candidate(episode) }

    def candidate(episode)
      Discovery::Candidate.new(
        title: episode['name'],
        url: episode.dig('external_urls', 'spotify'),
        published_on: episode['release_date'],
        show_name: episode.dig('show', 'name'),
        source: 'spotify',
        image_url: episode['images']&.first&.fetch('url', nil),
        duration: episode['duration_ms'] && (episode['duration_ms'] / 1000)
      )
    end
  end
end

# Runs the sweeps, sifts what they return, and reports.
class FindEntries
  WORKERS = 6

  IGNORE_FILE = File.expand_path('../ignore.yml', __dir__)

  YOUTUBE_CHANNEL = %r{youtube\.com/(?:@|channel/|c/|user/)}

  Show = Struct.new(:name, :url, :feed_url, :own, keyword_init: true)

  # At or below this many episodes, a show is read whole; above it, for his name.
  #
  # The number is low because a feed that stops at a round one is a window rather
  # than a catalogue: fifteen is every YouTube channel, and ten, twenty and
  # twenty-five are where podcast hosts cut theirs. Reading a window whole reports
  # the recent end of Mindscape, Conversations with Tyler and Tim Ferriss in full,
  # which is 448 candidates where there were 19.
  SHORT_CATALOGUE = 9

  def self.default_list = YAML.load_file(File.join(ROOT, 'list.yml'), aliases: true)

  def self.default_ignore = File.exist?(IGNORE_FILE) ? YAML.load_file(IGNORE_FILE) : {}

  def initialize(options, list: self.class.default_list, ignore: self.class.default_ignore)
    @options = options
    @list = list
    @index = Discovery::Index.new(@list)
    @ignore = Discovery::Ignore.new(ignore)
    @ignored = []
    @finder = FeedFinder.new
    @unreachable = Queue.new
    @skipped = []
    @swept = Hash.new(0)
  end

  def run
    prepare_spotify
    candidates = []
    candidates.concat(itunes_candidates) if source?('itunes')
    candidates.concat(spotify_candidates) if source?('spotify')
    candidates.concat(feed_candidates) if source?('feeds')
    candidates.concat(extra_feed_candidates)

    @unreachable_names = drain(@unreachable).sort
    novel, known = Discovery.sift(dedupe(candidates), @index)
    report(sort(reject_ignored(novel)), known)
  end

  private

  def log(message) = @options[:json] ? warn(message) : puts(message)

  def source?(name) = @options[:sources].include?(name)

  def itunes_candidates
    found = ItunesSweep.candidates(method(:log)).select { |candidate| about_deutsch?(candidate) }
    @swept[:searches] = ItunesSweep::TERMS.size
    found
  end

  def spotify_candidates
    return [] unless @spotify

    found = SpotifySweep.search(@spotify, method(:log)) { |candidate| about_deutsch?(candidate) }
    @swept[:spotify_searches] = SpotifySweep::TERMS.size
    found
  end

  # Built before the sweeps, which read shows in parallel and share the one token.
  # A sweep that would never ask Spotify anything says nothing about it.
  def prepare_spotify
    @spotify = nil
    return unless source?('spotify') || shows_in_list.any? { |show| Spotify.show_id(show.url) }

    client = Spotify.configured? ? Spotify::Client.new : nil
    @spotify = client if client&.usable?
    return if @spotify

    @skipped << if client
                  'Spotify (the credentials were refused)'
                else
                  'Spotify (set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET to sweep it)'
                end
  end

  # A show that has had him on once is the likeliest to have him on again, so the
  # whole back catalogue of every show in the list gets read.
  def feed_candidates
    shows = shows_in_list
    @swept[:shows] = shows.size
    in_parallel(shows) { |show| sweep_show(show) }
  end

  def extra_feed_candidates
    in_parallel(@options[:feeds]) do |feed_url|
      FeedReader.candidates(feed_url, show_name: nil, source: 'feed').select { |c| about_deutsch?(c) }
    end
  end

  def sweep_show(show)
    spotify_id = Spotify.show_id(show.url)
    return sweep_spotify_show(show, spotify_id) if spotify_id

    located = @finder.find(name: show.name, url: show.url, feed_url: show.feed_url)
    unless located
      @unreachable << show.name
      return []
    end

    feed_url, kind = located
    log "  reading #{show.name} (#{kind})"
    candidates = FeedReader.candidates(feed_url, show_name: show.name, source: kind.to_s)
    # A channel's Atom feed carries its last fifteen uploads whatever the channel
    # holds, so its length says nothing about the catalogue behind it.
    filter(candidates, own: show.own, windowed: kind == :youtube)
  end

  # The name filter earns its place on a long catalogue, where one appearance
  # hides among hundreds of episodes about something else. On a short one it only
  # throws away what a glance would judge: six of the seven Reason Is Fun episodes
  # name him nowhere in the title, and it dropped all six.
  #
  # `windowed` is a feed that states a fixed number of recent items rather than
  # everything it has, where a small count is no evidence of a small show.
  def filter(candidates, own: false, windowed: false)
    return candidates if own || (!windowed && candidates.size <= SHORT_CATALOGUE)

    candidates.select { |candidate| about_deutsch?(candidate) }
  end

  # A show that lives on Spotify has no feed to find, and the finder reported every
  # one of them as unreachable until this asked Spotify instead.
  def sweep_spotify_show(show, spotify_id)
    unless @spotify
      @unreachable << show.name
      return []
    end

    log "  reading #{show.name} (spotify)"
    # Paged to its end rather than served as a window, so its length is the truth.
    filter(SpotifySweep.show(@spotify, spotify_id))
  end

  # Only the title is read for his name. A description is a poor test: on the
  # shows that discuss his work every week, every episode blurb names him.
  def about_deutsch?(candidate) = EpisodeMatcher.names_subject?(candidate.title)

  def shows_in_list
    @shows_in_list ||= collect_shows
  end

  def collect_shows
    shows = {}

    @list.each_value do |entries|
      next unless entries.is_a?(Array)

      entries.each do |entry|
        next unless entry.is_a?(Hash)

        show = entry['show']
        add_show(shows, show['name'], show['url'], show['feed_url']) if show.is_a?(Hash)
      end
    end

    (@list['other'] || []).each { |entry| add_channel(shows, entry) }
    shows.values
  end

  def add_show(shows, name, url, feed_url)
    return if url.to_s.empty? && feed_url.to_s.empty?
    return unless url.to_s.start_with?('http') || feed_url

    shows[[name, url]] ||= Show.new(name: name, url: url, feed_url: feed_url, own: false)
  end

  # His own channel is in `other` as one link, and the list enumerates nothing from
  # it — the anthology collects appearances, and a channel of his own uploads is
  # covered by the link. `--own-channel` sweeps it anyway, for the case that earns
  # it: a talk he gave elsewhere that exists nowhere but there.
  #
  # `other` also holds single videos — a BBC documentary among them, whose channel
  # is a Dutch television archive — so only a channel-shaped URL is ever swept.
  def add_channel(shows, entry)
    return unless @options[:own_channel]

    url = entry['url']
    return unless @finder.youtube?(url) && url.match?(YOUTUBE_CHANNEL)

    shows[[entry['name'], url]] ||= Show.new(name: entry['name'], url: url, feed_url: nil, own: true)
  end

  def in_parallel(items)
    return [] if items.empty?

    queue = Queue.new
    items.each { |item| queue << item }
    queue.close
    results = Queue.new

    Array.new([WORKERS, items.size].min) do
      Thread.new do
        while (item = queue.pop)
          yield(item).each { |candidate| results << candidate }
        end
      end
    end.each(&:join)

    drain(results)
  end

  def drain(queue) = Array.new(queue.size) { queue.pop }

  # The same episode arrives from Apple and from the show's own feed, under
  # different URLs and pointing at different copies of the file, so one key cannot
  # catch it. A candidate is a repeat if it shares any key with one already kept.
  def dedupe(candidates)
    seen = Set.new
    candidates.select do |candidate|
      keys = candidate_keys(candidate)
      next false if keys.any? { |key| seen.include?(key) }

      seen.merge(keys)
      true
    end
  end

  def candidate_keys(candidate)
    [
      Discovery.normalize_url(candidate.url),
      Discovery.normalize_audio_url(candidate.audio_url),
      "#{Discovery.fold(candidate.show_name)}|#{Discovery.fold(candidate.title)}"
    ].compact
  end

  # After the sift, not before: a candidate the list already holds is reported as
  # already held, whatever the ignore file says about its show.
  def reject_ignored(candidates)
    candidates.reject do |candidate|
      reason = @ignore.reject(candidate)
      @ignored << [candidate, reason] if reason
      reason
    end
  end

  def sort(candidates)
    candidates.sort_by { |candidate| date_of(candidate) || Date.new(1900, 1, 1) }.reverse
  end

  def date_of(candidate)
    value = candidate.published_on
    return nil unless value

    value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def since_filter(candidates)
    return candidates unless @options[:since]

    candidates.select { |candidate| (date = date_of(candidate)) && date >= @options[:since] }
  end

  def report(novel, known)
    novel = since_filter(novel)
    @options[:json] ? report_json(novel, known) : report_text(novel, known)
  end

  def report_json(novel, known)
    puts JSON.pretty_generate(
      'swept' => @swept,
      'new' => novel.map { |candidate| json_candidate(candidate) },
      'unreachable_shows' => @unreachable_names,
      'skipped_sources' => @skipped,
      'ignored_count' => @ignored.size,
      'ignored' => (@options[:all] ? @ignored.map { |c, reason| { 'title' => c.title, 'reason' => reason } } : []),
      'known_count' => known.size,
      'known' => (@options[:all] ? known.map { |c, reason| { 'title' => c.title, 'reason' => reason } } : [])
    )
  end

  def json_candidate(candidate)
    candidate.to_h.transform_keys(&:to_s).merge('published_on' => date_of(candidate)&.to_s)
  end

  def report_text(novel, known)
    puts
    searches = [
      ("#{@swept[:searches]} Apple searches" if @swept[:searches].positive?),
      ("#{@swept[:spotify_searches]} Spotify searches" if @swept[:spotify_searches].positive?)
    ].compact
    puts "Swept #{@swept[:shows]} shows#{searches.empty? ? '' : " and #{searches.join(' and ')}"}: " \
         "#{novel.size} to look at, #{known.size} already listed, #{@ignored.size} ignored."
    puts

    novel.each { |candidate| print_candidate(candidate) }
    print_group('Already listed', known) if @options[:all]
    print_group('Ignored', @ignored) if @options[:all]
    print_unreachable
    print_skipped
  end

  def print_candidate(candidate)
    puts "  #{date_of(candidate) || '          '}  #{candidate.show_name}"
    puts "              #{candidate.title}"
    puts "              #{candidate.url}" if candidate.url
    puts "              audio: #{candidate.audio_url}" if candidate.audio_url
    puts "              via #{candidate.source}"
    puts
  end

  def print_group(heading, entries)
    puts "#{heading} (#{entries.size}):"
    entries.each { |candidate, reason| puts "  #{candidate.title} — #{reason}" }
    puts
  end

  def print_skipped
    return if @skipped.empty?

    @skipped.each { |source| puts "Not swept: #{source}" }
    puts
  end

  def print_unreachable
    return if @unreachable_names.empty?

    puts "No feed found for #{@unreachable_names.size} shows — they were not swept:"
    @unreachable_names.each { |name| puts "  #{name}" }
    puts
  end
end

def parse_options(argv)
  options = { sources: %w[itunes spotify feeds], feeds: [], json: false, all: false, since: nil, own_channel: false }

  until argv.empty?
    case (flag = argv.shift)
    when '--source' then options[:sources] = argv.shift.to_s.split(',')
    when '--feed' then options[:feeds] << argv.shift
    when '--since' then options[:since] = Date.parse(argv.shift)
    when '--json' then options[:json] = true
    when '--all' then options[:all] = true
    when '--own-channel' then options[:own_channel] = true
    else abort "unknown option: #{flag}"
    end
  end

  options
end

FindEntries.new(parse_options(ARGV)).run if $PROGRAM_NAME == __FILE__
