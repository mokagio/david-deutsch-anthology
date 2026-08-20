# frozen_string_literal: true

require 'json'
require 'minitest/autorun'

require_relative '../lib/media_resolver'

class MediaResolverArtworkTest < Minitest::Test
  FEED_URL = 'https://example.com/feed.xml'
  APPLE_URL = 'https://podcasts.apple.com/us/podcast/a-show/id123?i=456'

  def entry(url: 'https://example.com/one', show: { 'name' => 'A Show', 'feed_url' => FEED_URL })
    { 'title' => 'The Deutsch Files', 'url' => url, 'published_date' => '2024/01/11', 'show' => show }
  end

  def feed(item_image: nil, channel_image: nil)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>A Show</title>
          <link>https://example.com/</link>
          <description>A show.</description>
          #{"<itunes:image href=\"#{channel_image}\" />" if channel_image}
          <item>
            <title>The Deutsch Files with David Deutsch</title>
            <pubDate>Thu, 11 Jan 2024 00:00:00 +1100</pubDate>
            <enclosure url="https://example.com/a.mp3" type="audio/mpeg" length="1234567" />
            #{"<itunes:image href=\"#{item_image}\" />" if item_image}
          </item>
        </channel>
      </rss>
    XML
  end

  def itunes_results(episode_artwork:, collection_artwork:)
    JSON.generate(
      'results' => [
        { 'wrapperType' => 'track', 'kind' => 'podcast', 'collectionId' => 123,
          'artworkUrl600' => collection_artwork },
        { 'wrapperType' => 'podcastEpisode', 'trackId' => 456, 'artworkUrl600' => episode_artwork }
      ]
    )
  end

  # Every URL the resolver is allowed to reach; anything else answers as unreachable,
  # which is what a test that accidentally hits the network should look like.
  def resolve_artwork(entry, responses, sizes = {})
    get = lambda do |url, **_options|
      body = responses[url]
      body && HttpClient::Response.new(status: 200, headers: {}, body: body, url: url)
    end

    HttpClient.stub(:get, get) do
      MediaResolver.new(logger: ->(_message) {}, image_probe: ->(url) { sizes[url] }).resolve_artwork(entry)
    end
  end

  def size(width, height) = ImageProbe::Details.new(width, height)

  def test_uses_the_matched_items_own_image
    artwork = resolve_artwork(
      entry,
      FEED_URL => feed(item_image: 'https://example.com/episode.jpg',
                       channel_image: 'https://example.com/show.jpg')
    )

    assert_equal 'https://example.com/episode.jpg', artwork.image_url
    assert_equal :episode, artwork.scope
  end

  def test_falls_back_to_the_shows_image_when_the_episode_has_none
    artwork = resolve_artwork(entry, FEED_URL => feed(channel_image: 'https://example.com/show.jpg'))

    assert_equal 'https://example.com/show.jpg', artwork.image_url
    assert_equal :show, artwork.scope
  end

  def test_finds_nothing_when_neither_the_episode_nor_the_show_has_an_image
    artwork = resolve_artwork(entry, FEED_URL => feed)

    refute_predicate artwork, :found?
    assert_equal 'no artwork found', artwork.reason
  end

  def test_reads_the_image_off_the_entrys_own_page
    artwork = resolve_artwork(
      entry(show: { 'name' => 'A Show' }),
      'https://example.com/one' => '<meta property="og:image" content="https://example.com/page.jpg" />'
    )

    assert_equal 'https://example.com/page.jpg', artwork.image_url
    assert_equal :episode, artwork.scope
  end

  def test_ignores_an_image_that_is_not_an_absolute_url
    artwork = resolve_artwork(
      entry,
      FEED_URL => feed(item_image: '/episode.jpg', channel_image: 'https://example.com/show.jpg')
    )

    assert_equal 'https://example.com/show.jpg', artwork.image_url
  end

  def test_takes_apples_episode_artwork_when_it_is_the_episodes_own
    artwork = resolve_artwork(
      entry(url: APPLE_URL, show: { 'name' => 'A Show' }),
      apple_lookup => itunes_results(episode_artwork: 'https://example.com/episode.jpg',
                                     collection_artwork: 'https://example.com/show.jpg')
    )

    assert_equal 'https://example.com/episode.jpg', artwork.image_url
    assert_equal :episode, artwork.scope
  end

  # Apple answers with the show's logo for an episode that has none of its own, so
  # an artwork identical to the collection's is the show's however Apple files it.
  def test_treats_apple_artwork_matching_the_collections_as_the_shows
    artwork = resolve_artwork(
      entry(url: APPLE_URL, show: { 'name' => 'A Show' }),
      apple_lookup => itunes_results(episode_artwork: 'https://example.com/show.jpg',
                                     collection_artwork: 'https://example.com/show.jpg')
    )

    assert_equal 'https://example.com/show.jpg', artwork.image_url
    assert_equal :show, artwork.scope
  end

  def test_prefers_a_feed_items_image_to_apples_episode_artwork
    artwork = resolve_artwork(
      entry(url: APPLE_URL, show: { 'name' => 'A Show', 'feed_url' => FEED_URL }),
      FEED_URL => feed(item_image: 'https://example.com/episode.jpg'),
      apple_lookup => itunes_results(episode_artwork: 'https://example.com/apple.jpg',
                                     collection_artwork: 'https://example.com/show.jpg')
    )

    assert_equal 'https://example.com/episode.jpg', artwork.image_url
  end

  # `og:image` on a TED talk page is a wide banner crop, which a client would show
  # letterboxed or cropped through the middle of the subject.
  def test_passes_over_a_picture_that_is_not_square
    artwork = resolve_artwork(
      entry,
      { FEED_URL => feed(item_image: 'https://example.com/banner.jpg',
                         channel_image: 'https://example.com/show.jpg') },
      { 'https://example.com/banner.jpg' => size(1050, 550) }
    )

    assert_equal 'https://example.com/show.jpg', artwork.image_url
  end

  def test_records_the_size_it_measured
    artwork = resolve_artwork(
      entry,
      { FEED_URL => feed(item_image: 'https://example.com/episode.jpg') },
      { 'https://example.com/episode.jpg' => size(3000, 3000) }
    )

    assert_equal '3000×3000', artwork.size
  end

  def apple_lookup = 'https://itunes.apple.com/lookup?id=123&entity=podcastEpisode&limit=200'
end
