# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/feed_builder'

class FeedBuilderTest < Minitest::Test
  def interview(title:, url:, audio_url: 'https://example.com/a.mp3', date: '2024/01/11', show: 'A Show')
    {
      'title' => title, 'url' => url, 'audio_url' => audio_url,
      'published_date' => date, 'show' => { 'name' => show }
    }.compact
  end

  def probe(type: 'audio/mpeg', length: 1234)
    ->(_url) { Enclosure::Details.new(type: type, length: length) }
  end

  def test_builds_an_episode_from_an_entry_with_audio
    build = FeedBuilder.build(
      [interview(title: 'An interview', url: 'https://example.com/one', show: 'EconTalk')],
      probe: probe
    )

    episode = build.episodes.fetch(0)

    assert_empty build.skipped
    assert_equal 'An interview', episode[:title]
    assert_equal 'https://example.com/one', episode[:guid]
    assert_equal 'https://example.com/a.mp3', episode[:audio_url]
    assert_equal 'audio/mpeg', episode[:type]
    assert_equal 1234, episode[:length]
    assert_equal 'Interview on EconTalk', episode[:description]
  end

  def test_skips_an_entry_with_no_audio_url
    build = FeedBuilder.build(
      [interview(title: 'A video', url: 'https://example.com/one', audio_url: nil)],
      probe: probe
    )

    assert_empty build.episodes
    assert_equal 'no audio_url', build.skipped.fetch(0).reason
  end

  def test_skips_audio_the_probe_cannot_reach
    build = FeedBuilder.build(
      [interview(title: 'An interview', url: 'https://example.com/one')],
      probe: ->(_url) { nil }
    )

    assert_empty build.episodes
    assert_includes build.skipped.fetch(0).reason, 'could not read'
  end

  def test_skips_audio_with_no_byte_count_because_clients_reject_it
    build = FeedBuilder.build(
      [interview(title: 'An interview', url: 'https://example.com/one')],
      probe: probe(length: 0)
    )

    assert_empty build.episodes
    assert_includes build.skipped.fetch(0).reason, 'could not read'
  end

  def test_lists_the_newest_episode_first
    build = FeedBuilder.build(
      [
        interview(title: 'Older', url: 'https://example.com/old',
                  audio_url: 'https://example.com/old.mp3', date: '2020/03/01'),
        interview(title: 'Newer', url: 'https://example.com/new',
                  audio_url: 'https://example.com/new.mp3', date: '2024/03/01')
      ],
      probe: probe
    )

    assert_equal %w[Newer Older], build.episodes.map { |episode| episode[:title] }
  end

  def test_emits_one_episode_when_two_entries_share_an_audio_file
    build = FeedBuilder.build(
      [
        interview(title: 'The video', url: 'https://youtube.com/watch?v=1'),
        interview(title: 'The episode', url: 'https://example.com/one')
      ],
      probe: probe
    )

    assert_equal 1, build.episodes.size
  end
end
