# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/feed_builder'

class FeedBuilderTest < Minitest::Test
  def interview(title:, url:, audio_url: 'https://example.com/a.mp3', date: '2024/01/11', show: 'A Show')
    {
      'title' => title, 'url' => url, 'audio' => audio_url && { 'url' => audio_url },
      'published_date' => date, 'show' => { 'name' => show }
    }.compact
  end

  def probe(type: 'audio/mpeg', length: 1234567)
    ->(_url) { Enclosure::Details.new(type: type, length: length) }
  end

  def test_builds_an_episode_from_an_entry_with_audio
    build = FeedBuilder.build(
      { 'podcast_interviews' => [interview(title: 'An interview', url: 'https://example.com/one', show: 'EconTalk')] },
      probe: probe
    )

    episode = build.episodes.fetch(0)

    assert_empty build.skipped
    assert_equal 'An interview', episode[:title]
    assert_equal 'https://example.com/one', episode[:guid]
    assert_equal 'https://example.com/a.mp3', episode[:audio_url]
    assert_equal 'audio/mpeg', episode[:type]
    assert_equal 1234567, episode[:length]
    assert_equal 'Interview', episode[:label]
    assert_equal 'EconTalk', episode[:show_name]
  end

  def test_uses_the_recorded_type_and_length_without_probing
    entry = interview(title: 'An interview', url: 'https://example.com/one')
    entry['audio'].merge!('type' => 'audio/x-m4a', 'length' => 9_999_999)

    build = FeedBuilder.build(
      { 'podcast_interviews' => [entry] },
      probe: ->(_url) { flunk 'should not probe a recorded entry' }
    )

    episode = build.episodes.fetch(0)

    assert_equal 'audio/x-m4a', episode[:type]
    assert_equal 9_999_999, episode[:length]
  end

  def test_probes_when_only_one_of_type_and_length_is_recorded
    entry = interview(title: 'An interview', url: 'https://example.com/one')
    entry['audio']['length'] = 999

    build = FeedBuilder.build(
      { 'podcast_interviews' => [entry] },
      probe: probe(type: 'audio/mpeg', length: 1234567)
    )

    assert_equal 1234567, build.episodes.fetch(0)[:length]
  end

  def test_publishes_a_talk_that_has_audio
    talk = {
      'title' => 'Chemical scum', 'url' => 'https://ted.com/talk',
      'audio' => { 'url' => 'https://example.com/talk.mp3' },
      'delivered_date' => '2005/07/14', 'show' => { 'name' => 'TED Talks Daily' }
    }

    build = FeedBuilder.build({ 'talks' => [talk] }, probe: probe)

    episode = build.episodes.fetch(0)

    assert_equal 'Chemical scum', episode[:title]
    assert_equal 'Talk', episode[:label]
    assert_equal 2005, episode[:published_at].year
  end

  def test_ignores_sections_that_are_not_published
    build = FeedBuilder.build(
      { 'books' => [{ 'title' => 'A book', 'audio' => { 'url' => 'https://example.com/a.mp3' } }] },
      probe: probe
    )

    assert_empty build.episodes
    assert_empty build.skipped
  end

  def test_orders_talks_and_interviews_together_by_date
    talk = {
      'title' => 'Old talk', 'url' => 'https://ted.com/talk',
      'audio' => { 'url' => 'https://example.com/talk.mp3' },
      'delivered_date' => '2005/07/14', 'show' => { 'name' => 'TED' }
    }

    build = FeedBuilder.build(
      {
        'talks' => [talk],
        'podcast_interviews' => [interview(title: 'Recent', url: 'https://example.com/one')]
      },
      probe: probe
    )

    assert_equal ['Recent', 'Old talk'], build.episodes.map { |episode| episode[:title] }
  end

  def test_skips_an_entry_with_no_audio
    build = FeedBuilder.build(
      { 'podcast_interviews' => [interview(title: 'A video', url: 'https://example.com/one', audio_url: nil)] },
      probe: probe
    )

    assert_empty build.episodes
    assert_equal 'no audio url', build.skipped.fetch(0).reason
  end

  def test_skips_audio_the_probe_cannot_reach
    build = FeedBuilder.build(
      { 'podcast_interviews' => [interview(title: 'An interview', url: 'https://example.com/one')] },
      probe: ->(_url) { nil }
    )

    assert_empty build.episodes
    assert_includes build.skipped.fetch(0).reason, 'could not read'
  end

  def test_skips_audio_with_no_byte_count_because_clients_reject_it
    build = FeedBuilder.build(
      { 'podcast_interviews' => [interview(title: 'An interview', url: 'https://example.com/one')] },
      probe: probe(length: 0)
    )

    assert_empty build.episodes
    assert_includes build.skipped.fetch(0).reason, 'too small'
  end

  # acast answers a size request with two bytes of text/plain, which a
  # positive-number check waves through and no client can play.
  def test_skips_a_recorded_length_too_small_to_be_an_episode
    entry = interview(title: 'A stub', url: 'https://example.com/one')
    entry['audio'].merge!('type' => 'audio/mpeg', 'length' => 2)

    build = FeedBuilder.build(
      { 'podcast_interviews' => [entry] },
      probe: ->(_url) { flunk 'should not probe a recorded entry' }
    )

    assert_empty build.episodes
    assert_includes build.skipped.fetch(0).reason, 'audio length 2 is too small'
  end

  def test_lists_the_newest_episode_first
    build = FeedBuilder.build(
      { 'podcast_interviews' => [
        interview(title: 'Older', url: 'https://example.com/old',
                  audio_url: 'https://example.com/old.mp3', date: '2020/03/01'),
        interview(title: 'Newer', url: 'https://example.com/new',
                  audio_url: 'https://example.com/new.mp3', date: '2024/03/01')
      ] },
      probe: probe
    )

    assert_equal %w[Newer Older], build.episodes.map { |episode| episode[:title] }
  end

  def test_emits_one_episode_when_two_entries_share_an_audio_file
    build = FeedBuilder.build(
      { 'podcast_interviews' => [
        interview(title: 'The video', url: 'https://youtube.com/watch?v=1'),
        interview(title: 'The episode', url: 'https://example.com/one')
      ] },
      probe: probe
    )

    assert_equal 1, build.episodes.size
  end

  # The show's own site and its Apple listing name the same file, one of them
  # through a download counter and a `?dest-id=`, which a string compare misses.
  def test_emits_one_episode_when_the_same_file_carries_tracking_decoration
    build = FeedBuilder.build(
      { 'podcast_interviews' => [
        interview(title: 'From the site', url: 'https://nav.al/one',
                  audio_url: 'https://traffic.libsyn.com/secure/naval/Naval.mp3'),
        interview(title: 'From Apple', url: 'https://podcasts.apple.com/one',
                  audio_url: 'https://chrt.fm/track/ABC/traffic.libsyn.com/secure/naval/Naval.mp3?dest-id=1103966')
      ] },
      probe: probe
    )

    assert_equal 1, build.episodes.size
  end

  def test_publishes_the_entry_image
    entry = interview(title: 'An interview', url: 'https://example.com/one')
            .merge('image_url' => 'https://example.com/episode.jpg')

    build = FeedBuilder.build({ 'podcast_interviews' => [entry] }, probe: probe)

    assert_equal 'https://example.com/episode.jpg', build.episodes.fetch(0)[:image_url]
  end

  def test_falls_back_to_the_show_image
    entry = interview(title: 'An interview', url: 'https://example.com/one')
    entry['show']['image_url'] = 'https://example.com/show.jpg'

    build = FeedBuilder.build({ 'podcast_interviews' => [entry] }, probe: probe)

    assert_equal 'https://example.com/show.jpg', build.episodes.fetch(0)[:image_url]
  end

  def test_prefers_the_entry_image_over_the_show_image
    entry = interview(title: 'An interview', url: 'https://example.com/one')
            .merge('image_url' => 'https://example.com/episode.jpg')
    entry['show']['image_url'] = 'https://example.com/show.jpg'

    build = FeedBuilder.build({ 'podcast_interviews' => [entry] }, probe: probe)

    assert_equal 'https://example.com/episode.jpg', build.episodes.fetch(0)[:image_url]
  end

  def test_attributes_an_episode_to_the_show_that_published_it
    entry = interview(title: 'An interview', url: 'https://econtalk.org/deutsch')
    entry['podcast_url'] = 'https://pca.st/abcd1234'
    entry['show']['url'] = 'https://econtalk.org'

    episode = FeedBuilder.build({ 'podcast_interviews' => [entry] }, probe: probe).episodes.fetch(0)

    assert_equal 'https://econtalk.org/deutsch', episode[:guid]
    assert_equal 'https://econtalk.org/deutsch', episode[:page_url]
    assert_equal 'https://econtalk.org', episode[:show_url]
  end

  def test_prefers_the_shows_own_video_to_an_aggregator_listing
    entry = interview(title: 'An interview', url: nil)
    entry['podcast_url'] = 'https://podcasts.apple.com/us/podcast/one/id1?i=2'
    entry['youtube_url'] = 'https://www.youtube.com/watch?v=abcd1234'

    episode = FeedBuilder.build({ 'podcast_interviews' => [entry] }, probe: probe).episodes.fetch(0)

    assert_equal 'https://www.youtube.com/watch?v=abcd1234', episode[:guid]
  end

  def test_stamps_a_recorded_day_at_midday_utc
    build = FeedBuilder.build(
      { 'podcast_interviews' => [interview(title: 'An interview', url: 'https://example.com/one')] },
      probe: probe
    )

    assert_equal Time.utc(2024, 1, 11, 12, 0, 0), build.episodes.fetch(0)[:published_at]
  end

  def test_prefers_the_instant_the_source_feed_stated
    entry = interview(title: 'An interview', url: 'https://example.com/one')
                .merge('published_at' => 'Thu, 11 Jan 2024 09:30:00 +0000')

    build = FeedBuilder.build({ 'podcast_interviews' => [entry] }, probe: probe)

    assert_equal Time.utc(2024, 1, 11, 9, 30, 0), build.episodes.fetch(0)[:published_at]
  end

  def test_publishes_the_recorded_runtime_as_a_clock_face
    entry = interview(title: 'An interview', url: 'https://example.com/one')
    entry['audio']['duration'] = 3754

    build = FeedBuilder.build({ 'podcast_interviews' => [entry] }, probe: probe)

    assert_equal '01:02:34', build.episodes.fetch(0)[:duration]
  end

  def test_publishes_an_episode_whose_runtime_is_not_recorded
    build = FeedBuilder.build(
      { 'podcast_interviews' => [interview(title: 'An interview', url: 'https://example.com/one')] },
      probe: probe
    )

    assert_empty build.skipped
    assert_nil build.episodes.fetch(0)[:duration]
  end

  def test_publishes_an_episode_with_no_image
    build = FeedBuilder.build(
      { 'podcast_interviews' => [interview(title: 'An interview', url: 'https://example.com/one')] },
      probe: probe
    )

    assert_empty build.skipped
    assert_nil build.episodes.fetch(0)[:image_url]
  end
end
