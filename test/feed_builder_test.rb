# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/audio_dictionary'
require_relative '../lib/feed_builder'

class FeedBuilderTest < Minitest::Test
  def interview(title:, url:, date: '2024/01/11', show: 'A Show')
    { 'title' => title, 'url' => url, 'published_date' => date, 'show' => { 'name' => show } }
  end

  def entry(audio_url: 'https://example.com/a.mp3', length: 1234, **extra)
    { 'audio_url' => audio_url, 'type' => 'audio/mpeg', 'length' => length }.merge(extra)
  end

  def dictionary(entries)
    AudioDictionary.new(entries: entries)
  end

  def test_builds_an_episode_from_a_resolved_entry
    build = FeedBuilder.build(
      [interview(title: 'An interview', url: 'https://example.com/one', show: 'EconTalk')],
      dictionary({ 'https://example.com/one' => entry })
    )

    episode = build.episodes.fetch(0)

    assert_empty build.skipped
    assert_equal 'An interview', episode[:title]
    assert_equal 'https://example.com/one', episode[:guid]
    assert_equal 'https://example.com/a.mp3', episode[:audio_url]
    assert_equal 'Interview on EconTalk', episode[:description]
  end

  def test_skips_an_interview_the_dictionary_has_never_seen
    build = FeedBuilder.build(
      [interview(title: 'An interview', url: 'https://example.com/one')],
      dictionary({})
    )

    assert_empty build.episodes
    assert_equal 'not resolved yet', build.skipped.fetch(0).reason
  end

  def test_skips_an_interview_with_no_audio_and_reports_why
    build = FeedBuilder.build(
      [interview(title: 'A video', url: 'https://example.com/one')],
      dictionary({ 'https://example.com/one' => { 'audio_url' => nil, 'reason' => 'no audio source found' } })
    )

    assert_empty build.episodes
    assert_equal 'no audio source found', build.skipped.fetch(0).reason
  end

  def test_skips_audio_with_no_byte_count_because_clients_reject_it
    build = FeedBuilder.build(
      [interview(title: 'An interview', url: 'https://example.com/one')],
      dictionary({ 'https://example.com/one' => entry(length: 0) })
    )

    assert_empty build.episodes
    assert_equal 'audio file size unknown', build.skipped.fetch(0).reason
  end

  def test_lists_the_newest_episode_first
    build = FeedBuilder.build(
      [
        interview(title: 'Older', url: 'https://example.com/old', date: '2020/03/01'),
        interview(title: 'Newer', url: 'https://example.com/new', date: '2024/03/01')
      ],
      dictionary(
        'https://example.com/old' => entry(audio_url: 'https://example.com/old.mp3'),
        'https://example.com/new' => entry(audio_url: 'https://example.com/new.mp3')
      )
    )

    assert_equal %w[Newer Older], build.episodes.map { |episode| episode[:title] }
  end

  def test_emits_one_episode_when_two_entries_share_an_audio_file
    build = FeedBuilder.build(
      [
        interview(title: 'The video', url: 'https://youtube.com/watch?v=1'),
        interview(title: 'The episode', url: 'https://example.com/one')
      ],
      dictionary(
        'https://youtube.com/watch?v=1' => entry,
        'https://example.com/one' => entry
      )
    )

    assert_equal 1, build.episodes.size
  end
end
