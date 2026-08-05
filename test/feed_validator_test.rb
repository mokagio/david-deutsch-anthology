# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/feed_validator'

class FeedValidatorTest < Minitest::Test
  def feed(item_body)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <rss version="2.0">
        <channel>
          <title>David Deutsch Podcast Interviews</title>
          <link>https://example.com/</link>
          <description>Interviews.</description>
          <item>
            #{item_body}
          </item>
        </channel>
      </rss>
    XML
  end

  def playable_item(enclosure: '<enclosure url="https://example.com/a.mp3" type="audio/mpeg" length="123" />')
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

  def test_rejects_an_item_with_no_enclosure
    errors = FeedValidator.errors(feed(playable_item(enclosure: '')))

    assert_equal 1, errors.size
    assert_includes errors.first, 'no <enclosure>'
  end

  def test_rejects_an_enclosure_pointing_at_a_web_page
    enclosure = '<enclosure url="https://example.com/episode" type="text/html" length="123" />'
    errors = FeedValidator.errors(feed(playable_item(enclosure: enclosure)))

    assert_includes errors.join, 'is not an audio type'
  end

  def test_rejects_a_zero_length_enclosure
    enclosure = '<enclosure url="https://example.com/a.mp3" type="audio/mpeg" length="0" />'
    errors = FeedValidator.errors(feed(playable_item(enclosure: enclosure)))

    assert_includes errors.join, 'not a positive byte count'
  end

  def test_rejects_a_relative_enclosure_url
    enclosure = '<enclosure url="/a.mp3" type="audio/mpeg" length="123" />'
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

  def test_the_generated_feed_is_playable
    path = File.expand_path('../public/podcast.rss', __dir__)
    skip 'run `ruby generate_podcast_rss.rb` first' unless File.exist?(path)

    assert_empty FeedValidator.errors(File.read(path))
  end
end
