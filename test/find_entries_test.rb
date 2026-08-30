# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'stringio'

require_relative '../.claude/skills/find-entries/scripts/find_entries'

# Drives the sweep end to end with the network stubbed, because everything that
# has gone wrong here went wrong between the list and the feed: a channel page
# that names its channel under a key we were not reading, and a single video in
# `other` swept as though it were a channel of his.
class FindEntriesTest < Minitest::Test
  CHANNEL = 'UCCVbf1O4pHLYE937yz9F1UA'

  def setup
    @responses = {}
    @requested = []
    stub_http
  end

  def teardown
    %i[get post_form].each do |verb|
      HttpClient.singleton_class.send(:remove_method, verb)
      HttpClient.singleton_class.send(:alias_method, verb, :"#{verb}_without_stub")
      HttpClient.singleton_class.send(:remove_method, :"#{verb}_without_stub")
    end
    ENV.delete('SPOTIFY_CLIENT_ID')
    ENV.delete('SPOTIFY_CLIENT_SECRET')
  end

  def stub_http
    test = self
    HttpClient.singleton_class.send(:alias_method, :get_without_stub, :get)
    HttpClient.singleton_class.send(:alias_method, :post_form_without_stub, :post_form)
    HttpClient.singleton_class.send(:define_method, :get) { |url, **| test.respond(url) }
    HttpClient.singleton_class.send(:define_method, :post_form) { |url, **| test.respond(url) }
  end

  def respond(url)
    @requested << url
    body = @responses[url]
    body && HttpClient::Response.new(status: 200, headers: {}, body: body, url: url)
  end

  def serve(url, body) = @responses[url] = body

  # --- fixtures -----------------------------------------------------------

  def rss(*items, title: 'A Show', link: 'https://show.example')
    entries = items.each_with_index.map do |item, index|
      <<~ITEM
        <item>
          <title>#{item[:title]}</title>
          <link>#{item[:link] || "https://show.example/episode-#{index}"}</link>
          <pubDate>#{item[:date] || 'Mon, 06 Jun 2022 00:00:00 +0000'}</pubDate>
          <enclosure url="#{item[:audio] || "https://cdn.example/episode-#{index}.mp3"}" type="audio/mpeg" length="1000"/>
        </item>
      ITEM
    end

    <<~RSS
      <?xml version="1.0"?>
      <rss version="2.0"><channel>
        <title>#{title}</title><link>#{link}</link><description>d</description>
        #{entries.join}
      </channel></rss>
    RSS
  end

  def atom(*items, title: 'A Channel')
    entries = items.map do |item|
      <<~ITEM
        <entry>
          <title>#{item[:title]}</title>
          <link rel="alternate" href="#{item[:link]}"/>
          <published>#{item[:date] || '2024-06-06T00:00:00+00:00'}</published>
        </entry>
      ITEM
    end

    <<~ATOM
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>#{title}</title>
        #{entries.join}
      </feed>
    ATOM
  end

  def channel_feed_url(id = CHANNEL) = "https://www.youtube.com/feeds/videos.xml?channel_id=#{id}"

  def sweep(list, options: {}, ignore: {})
    defaults = { sources: %w[feeds], feeds: [], json: true, all: false, since: nil, own_channel: false }
    out = StringIO.new
    $stdout = out
    $stderr = StringIO.new
    FindEntries.new(defaults.merge(options), list: list, ignore: ignore).run
    JSON.parse(out.string)
  ensure
    $stdout = STDOUT
    $stderr = STDERR
  end

  def titles(report) = report['new'].map { |candidate| candidate['title'] }

  # --- his own channel ----------------------------------------------------

  # The list holds his channel as one link and enumerates nothing from it.
  OWN_CHANNEL_LIST = {
    'other' => [{ 'name' => "David's YouTube channel", 'url' => 'https://www.youtube.com/@DavidDeutschPhysicist' }]
  }.freeze

  def serve_own_channel
    serve('https://www.youtube.com/@DavidDeutschPhysicist',
          %(<link rel="alternate" href="#{channel_feed_url}"/>"externalId":"#{CHANNEL}"))
    serve(channel_feed_url,
          atom({ title: 'Why Are Flowers Beautiful?', link: 'https://www.youtube.com/watch?v=aaa' }))
  end

  def test_his_own_channel_is_not_swept_by_default
    serve_own_channel

    assert_empty sweep(OWN_CHANNEL_LIST)['new']
  end

  # Its uploads are titled by subject, not by guest, so the name filter cannot
  # apply — which is the whole reason sweeping it is opt-in.
  def test_own_channel_flag_sweeps_it_without_the_name_filter
    serve_own_channel

    assert_equal ['Why Are Flowers Beautiful?'], titles(sweep(OWN_CHANNEL_LIST, options: { own_channel: true }))
  end

  # `other` also holds single videos. One is a BBC documentary whose channel is a
  # Dutch television archive, which once contributed 18 episodes of 1980s music
  # journalism to a report.
  def test_a_single_video_in_other_is_never_swept_as_a_channel
    list = { 'other' => [{ 'name' => 'BBC Antenna Documentary', 'url' => 'https://www.youtube.com/watch?v=C6_gxo' }] }
    serve('https://www.youtube.com/watch?v=C6_gxo', %("channelId":"UCotherchannel00000000"))

    assert_empty sweep(list, options: { own_channel: true })['new']
    refute_includes @requested, 'https://www.youtube.com/watch?v=C6_gxo'
  end

  # --- Spotify --------------------------------------------------------------

  # The list holds a show that publishes on Spotify and nowhere else. The feed
  # finder has nothing to find for it, and it was reported unreachable every sweep.
  SPOTIFY_SHOW = 'https://open.spotify.com/show/5xD9XCKiagoraGYvL0UHrT'

  def spotify_show_list
    { 'podcast_interviews' => [
      { 'title' => 'An interview', 'show' => { 'name' => 'A Spotify Show', 'url' => SPOTIFY_SHOW } }
    ] }
  end

  def with_credentials
    ENV['SPOTIFY_CLIENT_ID'] = 'an-id'
    ENV['SPOTIFY_CLIENT_SECRET'] = 'a-secret'
    serve(Spotify::TOKEN_URL, JSON.dump({ 'access_token' => 'a-token' }))
  end

  def serve_spotify_show(*names)
    episodes = names.each_with_index.map do |name, index|
      { 'id' => "e#{index}", 'name' => name, 'release_date' => '2024-01-04',
        'external_urls' => { 'spotify' => "https://open.spotify.com/episode/e#{index}" } }
    end
    serve("#{Spotify::API}/shows/5xD9XCKiagoraGYvL0UHrT?market=US", JSON.dump({ 'name' => 'A Spotify Show' }))
    serve("#{Spotify::API}/shows/5xD9XCKiagoraGYvL0UHrT/episodes?market=US&limit=50",
          JSON.dump({ 'items' => episodes, 'next' => nil }))
  end

  def test_a_listed_spotify_show_is_read_through_the_api
    with_credentials
    serve_spotify_show('Deutsch on explanation')

    report = sweep(spotify_show_list, options: { sources: %w[feeds] })

    assert_equal ['Deutsch on explanation'], titles(report)
    assert_equal 'A Spotify Show', report['new'].first['show_name']
    assert_empty report['unreachable_shows']
  end

  # Without credentials nothing is guessed at: the show is named as unswept, the
  # way a show whose feed cannot be found already is.
  def test_without_credentials_spotify_is_said_to_be_skipped
    serve_spotify_show('Deutsch on explanation')

    report = sweep(spotify_show_list, options: { sources: %w[feeds] })

    assert_empty report['new']
    assert_equal ['A Spotify Show'], report['unreachable_shows']
    assert_includes report['skipped_sources'].join, 'SPOTIFY_CLIENT_ID'
  end

  def serve_spotify_search(*episodes)
    serve("#{Spotify::API}/search?q=david+deutsch&type=episode&market=US&limit=#{Spotify::SEARCH_PAGE}",
          JSON.dump({ 'episodes' => { 'items' => episodes, 'next' => nil } }))
  end

  def spotify_episode(id, name)
    { 'id' => id, 'name' => name, 'release_date' => '2024-01-04', 'duration_ms' => 60_000,
      'external_urls' => { 'spotify' => "https://open.spotify.com/episode/#{id}" },
      'audio_preview_url' => 'https://p.scdn.co/mp3-preview/clip.mp3' }
  end

  # An episode Spotify carries is a lead, never audio: the file is theirs to play,
  # and the preview it offers is thirty seconds long.
  def test_a_spotify_search_hit_carries_no_audio
    with_credentials
    serve_spotify_search(spotify_episode('e1', 'David Deutsch on explanation'))
    serve("#{Spotify::API}/episodes/e1?market=US",
          JSON.dump(spotify_episode('e1', 'David Deutsch on explanation').merge('show' => { 'name' => 'A Spotify Show' })))

    found = sweep({}, options: { sources: %w[spotify] })['new']

    assert_equal ['David Deutsch on explanation'], found.map { |candidate| candidate['title'] }
    assert_equal 'A Spotify Show', found.first['show_name']
    assert_nil found.first['audio_url']
    assert_equal 60, found.first['duration']
  end

  # Reading a hit back is a request of its own, so it is spent only on what the
  # name filter kept.
  def test_only_a_hit_worth_keeping_is_read_back
    with_credentials
    serve_spotify_search(spotify_episode('e1', 'David Deutsch on explanation'),
                         spotify_episode('e2', 'Some other guest entirely'))
    serve("#{Spotify::API}/episodes/e1?market=US",
          JSON.dump(spotify_episode('e1', 'David Deutsch on explanation').merge('show' => { 'name' => 'A Spotify Show' })))

    found = sweep({}, options: { sources: %w[spotify] })['new']

    assert_equal ['David Deutsch on explanation'], found.map { |candidate| candidate['title'] }
    refute_includes @requested, "#{Spotify::API}/episodes/e2?market=US"
  end

  def test_a_sweep_that_asks_spotify_nothing_says_nothing_about_it
    report = sweep({}, options: { sources: %w[itunes] })

    assert_empty report['skipped_sources']
  end

  # --- how much of a show's catalogue is read ------------------------------

  # Reason Is Fun is his and Lulie Tanett's, and only its first episode names him
  # in the title. The other six sat in a seven-episode feed the sweep was already
  # reading, and the name filter dropped every one.
  def show_list = { 'podcast_interviews' => [{ 'title' => 'An episode', 'show' => { 'name' => 'A Show', 'url' => 'https://show.example' } }] }

  def serve_catalogue(size)
    episodes = Array.new(size) { |n| { title: "Episode #{n} about something else" } }
    episodes << { title: 'Fun, Fury, Feeling' }
    serve('https://show.example', %(<link rel="alternate" type="application/rss+xml" href="https://show.example/feed.xml"/>))
    serve('https://show.example/feed.xml', rss(*episodes))
  end

  def test_a_short_catalogue_is_read_whole
    serve_catalogue(6)

    assert_includes titles(sweep(show_list)), 'Fun, Fury, Feeling'
  end

  def test_a_long_catalogue_is_read_for_his_name
    serve_catalogue(FindEntries::SHORT_CATALOGUE)

    assert_empty sweep(show_list)['new']
  end

  # --- locating a show's feed ---------------------------------------------

  def guest_channel_list(url = 'https://www.youtube.com/@guest')
    { 'podcast_interviews' => [{ 'title' => 'An old one', 'show' => { 'name' => 'Guest Show', 'url' => url } }] }
  end

  # A channel page links its own feed and names itself under `externalId` or
  # `browseId`; only a watch page uses `channelId`. Reading `channelId` alone left
  # 17 of 40 shows unswept and reported as though they held nothing new.
  {
    'a declared feed link' => %(<link rel="alternate" type="application/rss+xml" href="FEED"/>),
    'externalId' => %({"externalId":"#{CHANNEL}"}),
    'browseId' => %({"browseId":"#{CHANNEL}"}),
    'channelId' => %({"channelId":"#{CHANNEL}"})
  }.each do |description, page|
    define_method("test_finds_a_youtube_channel_feed_via_#{description.tr(' ', '_')}") do
      serve('https://www.youtube.com/@guest', page.sub('FEED', channel_feed_url))
      serve(channel_feed_url,
            atom({ title: 'David Deutsch on knowledge', link: 'https://www.youtube.com/watch?v=new' }))

      assert_equal ['David Deutsch on knowledge'], titles(sweep(guest_channel_list))
    end
  end

  def test_a_channel_url_needs_no_page_fetch
    serve(channel_feed_url, atom({ title: 'David Deutsch again', link: 'https://www.youtube.com/watch?v=n' }))
    report = sweep(guest_channel_list("https://www.youtube.com/channel/#{CHANNEL}"))

    assert_equal ['David Deutsch again'], titles(report)
    assert_equal [channel_feed_url], @requested
  end

  # A show nothing could locate is named, so a hole in the sweep does not read as
  # "nothing new on that show".
  def test_a_show_whose_feed_cannot_be_found_is_reported_not_dropped
    report = sweep(guest_channel_list('https://unreachable.example/show'))

    assert_equal ['Guest Show'], report['unreachable_shows']
  end

  # --- filtering ----------------------------------------------------------

  def rss_show_list
    { 'podcast_interviews' => [
      { 'title' => 'An old one', 'show' => { 'name' => 'A Show', 'feed_url' => 'https://show.example/feed' } }
    ] }
  end

  # A long catalogue only; a short one is read whole, which is what the sweep of a
  # show's back catalogue tests above pin down.
  def test_an_episode_that_never_names_him_is_not_a_candidate
    episodes = Array.new(FindEntries::SHORT_CATALOGUE) { |n| { title: 'Some other guest entirely', link: "https://show.example/#{n}" } }
    serve('https://show.example/feed',
          rss(*episodes, { title: 'David Deutsch on explanation', link: 'https://show.example/named' }))

    assert_equal ['David Deutsch on explanation'], titles(sweep(rss_show_list))
  end

  def test_the_ignore_file_drops_a_candidate_and_counts_it
    serve('https://show.example/feed', rss({ title: 'David Deutsch reads a chapter', link: 'https://show.example/1' }))
    report = sweep(rss_show_list, ignore: { 'titles' => ['reads a chapter'] })

    assert_empty report['new']
    assert_equal 1, report['ignored_count']
  end

  def test_since_keeps_only_what_came_after
    serve('https://show.example/feed',
          rss({ title: 'David Deutsch early', link: 'https://show.example/1',
                date: 'Mon, 06 Jun 2022 00:00:00 +0000' },
              { title: 'David Deutsch late', link: 'https://show.example/2',
                date: 'Fri, 06 Jun 2025 00:00:00 +0000' }))

    assert_equal ['David Deutsch late'], titles(sweep(rss_show_list, options: { since: Date.new(2024, 1, 1) }))
  end

  # --- one episode, several sources ---------------------------------------

  # Apple and the show's own feed describe the same conversation under different
  # URLs and point at different copies of the file.
  def test_the_same_episode_from_two_sources_is_reported_once
    serve('https://itunes.apple.com/search?term=david+deutsch&entity=podcastEpisode&limit=200',
          JSON.dump('results' => [{
                      'trackName' => 'David Deutsch on explanation',
                      'trackViewUrl' => 'https://podcasts.apple.com/us/podcast/x/id1?i=2',
                      'episodeUrl' => 'https://chrt.fm/track/AB/cdn.example/ep.mp3',
                      'releaseDate' => '2022-06-06T00:00:00Z',
                      'collectionName' => 'A Show'
                    }]))
    serve('https://show.example/feed',
          rss({ title: 'David Deutsch on explanation', link: 'https://show.example/1',
                audio: 'https://cdn.example/ep.mp3' }))

    report = sweep(rss_show_list, options: { sources: %w[itunes feeds] })

    assert_equal 1, report['new'].size
  end

  def test_an_entry_already_in_the_list_is_counted_as_known_not_new
    list = { 'podcast_interviews' => [
      { 'title' => 'David Deutsch on explanation', 'url' => 'https://show.example/1',
        'show' => { 'name' => 'A Show', 'feed_url' => 'https://show.example/feed' } }
    ] }
    serve('https://show.example/feed', rss({ title: 'David Deutsch on explanation', link: 'https://show.example/1' }))
    report = sweep(list)

    assert_empty report['new']
    assert_equal 1, report['known_count']
  end

  # --- options ------------------------------------------------------------

  def test_sweeping_his_own_channel_is_off_unless_asked_for
    refute parse_options([])[:own_channel]
    assert parse_options(['--own-channel'])[:own_channel]
  end

  def test_parses_the_remaining_flags
    options = parse_options(['--source', 'itunes', '--feed', 'https://a.example/f', '--since', '2025-01-01', '--json'])

    assert_equal %w[itunes], options[:sources]
    assert_equal ['https://a.example/f'], options[:feeds]
    assert_equal Date.new(2025, 1, 1), options[:since]
    assert options[:json]
  end

  def test_rejects_an_unknown_flag
    $stderr = StringIO.new
    assert_raises(SystemExit) { parse_options(['--nonsense']) }
  ensure
    $stderr = STDERR
  end
end
