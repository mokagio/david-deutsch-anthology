# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/feed_validator'

class FeedValidatorTest < Minitest::Test
  def feed(item_body, channel_body: '')
    <<~XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>David Deutsch Podcast Interviews</title>
          <link>https://example.com/</link>
          <description>Interviews.</description>
          #{channel_body}
          <item>
            #{item_body}
          </item>
        </channel>
      </rss>
    XML
  end

  def playable_item(enclosure: '<enclosure url="https://example.com/a.mp3" type="audio/mpeg" length="1234567" />')
    <<~XML
      <title>An interview</title>
      <guid isPermaLink="false">https://example.com/interview</guid>
      <pubDate>Thu, 11 Jan 2024 00:00:00 +1100</pubDate>
      #{enclosure}
    XML
  end

  def test_accepts_a_playable_feed
    assert_empty FeedValidator.errors(feed(playable_item))
  end

  def notes(href) = "<description><![CDATA[<a href='#{href}'>The Show</a>]]></description>".tr("'", '"')

  def test_rejects_a_relative_link_in_the_notes
    errors = FeedValidator.errors(feed(playable_item + notes('theshowsname')))

    assert_includes errors.join, 'is not absolute'
  end

  def test_accepts_absolute_links_in_the_notes
    assert_empty FeedValidator.errors(feed(playable_item + notes('https://example.com/show')))
  end

  def test_rejects_an_item_with_no_enclosure
    errors = FeedValidator.errors(feed(playable_item(enclosure: '')))

    assert_equal 1, errors.size
    assert_includes errors.first, 'no <enclosure>'
  end

  def test_rejects_an_enclosure_pointing_at_a_web_page
    enclosure = '<enclosure url="https://example.com/episode" type="text/html" length="1234567" />'
    errors = FeedValidator.errors(feed(playable_item(enclosure: enclosure)))

    assert_includes errors.join, 'is not an audio type'
  end

  def test_rejects_a_zero_length_enclosure
    enclosure = '<enclosure url="https://example.com/a.mp3" type="audio/mpeg" length="0" />'
    errors = FeedValidator.errors(feed(playable_item(enclosure: enclosure)))

    assert_includes errors.join, 'too small to be an episode'
  end

  def test_rejects_a_stub_length_that_is_positive_but_absurd
    enclosure = '<enclosure url="https://example.com/a.mp3" type="audio/mpeg" length="2" />'
    errors = FeedValidator.errors(feed(playable_item(enclosure: enclosure)))

    assert_includes errors.join, 'too small to be an episode'
  end

  def test_rejects_a_relative_enclosure_url
    enclosure = '<enclosure url="/a.mp3" type="audio/mpeg" length="1234567" />'
    errors = FeedValidator.errors(feed(playable_item(enclosure: enclosure)))

    assert_includes errors.join, 'not an absolute http(s) URL'
  end

  def test_rejects_an_item_with_no_guid
    item = playable_item.lines.reject { |line| line.include?('<guid') }.join
    errors = FeedValidator.errors(feed(item))

    assert_includes errors.join, 'missing <guid>'
  end

  def test_rejects_a_feed_that_is_not_well_formed
    errors = FeedValidator.errors('<rss><channel><title>Broken</title>')

    assert_equal 1, errors.size
    assert_includes errors.first, 'does not parse'
  end

  def test_accepts_artwork_on_the_channel_and_the_item
    xml = feed(
      playable_item + '<itunes:image href="https://example.com/episode.jpg" />',
      channel_body: '<itunes:image href="https://example.com/cover.jpg" />'
    )

    assert_empty FeedValidator.errors(xml)
  end

  def test_rejects_a_relative_item_image
    errors = FeedValidator.errors(feed(playable_item + '<itunes:image href="/episode.jpg" />'))

    assert_equal 1, errors.size
    assert_includes errors.first, '<itunes:image>'
  end

  def test_rejects_a_relative_channel_image
    errors = FeedValidator.errors(feed(playable_item, channel_body: '<itunes:image href="cover.jpg" />'))

    assert_equal ['channel: <itunes:image> href "cover.jpg" is not an absolute http(s) URL'], errors
  end

  # The generated feed is checked by `rake validate`, which runs after `generate`.
  # Asserting it here read whatever `public/` happened to contain, and `rake` runs
  # the tests first — so it passed or failed on the previous build's output.
end
