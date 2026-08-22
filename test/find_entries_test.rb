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
    HttpClient.singleton_class.send(:remove_method, :get)
    HttpClient.singleton_class.send(:alias_method, :get, :get_without_stub)
    HttpClient.singleton_class.send(:remove_method, :get_without_stub)
  end

  def stub_http
    test = self
    HttpClient.singleton_class.send(:alias_method, :get_without_stub, :get)
    HttpClient.singleton_class.send(:define_method, :get) { |url, **| test.respond(url) }
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

  def test_an_episode_that_never_names_him_is_not_a_candidate
    serve('https://show.example/feed',
          rss({ title: 'Some other guest entirely', link: 'https://show.example/1' },
              { title: 'David Deutsch on explanation', link: 'https://show.example/2' }))

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
