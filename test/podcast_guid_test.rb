# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/podcast_guid'

class PodcastGuidTest < Minitest::Test
  # The worked example the podcast namespace publishes alongside the rule.
  def test_matches_the_published_example
    assert_equal '917393e3-1b1e-5cef-ace4-edaa54e1f810',
                 PodcastGuid.for('https://mp3s.nashownotes.com/pc20rss.xml')
  end

  def test_ignores_what_the_seed_strips
    guid = PodcastGuid.for('https://example.com/feed.xml')

    assert_equal guid, PodcastGuid.for('http://example.com/feed.xml')
    assert_equal guid, PodcastGuid.for('example.com/feed.xml')
    assert_equal guid, PodcastGuid.for('https://example.com/feed.xml/')
  end

  def test_tells_two_feeds_apart
    refute_equal PodcastGuid.for('https://example.com/one.xml'),
                 PodcastGuid.for('https://example.com/two.xml')
  end
end
