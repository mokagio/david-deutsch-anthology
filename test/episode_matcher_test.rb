# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/episode_matcher'

class EpisodeMatcherTest < Minitest::Test
  def candidate(title:, published_on: '2024/01/11', audio_url: 'https://example.com/episode.mp3')
    EpisodeMatcher::Candidate.new(title: title, published_on: published_on, audio_url: audio_url)
  end

  def test_matches_a_differently_worded_title_on_the_same_day
    match = EpisodeMatcher.best_match(
      [candidate(title: 'David Deutsch on the Fabric of Reality')],
      title: 'The Fabric of Reality, with David Deutsch',
      published_on: '2024/01/11'
    )

    assert_equal 'David Deutsch on the Fabric of Reality', match.title
  end

  def test_matches_a_close_title_published_on_a_different_day
    match = EpisodeMatcher.best_match(
      [candidate(title: 'The Deutsch Files I', published_on: '2023/11/02')],
      title: 'The Deutsch Files I',
      published_on: '2024/01/11'
    )

    refute_nil match
  end

  def test_rejects_an_episode_that_never_names_the_subject
    match = EpisodeMatcher.best_match(
      [candidate(title: 'Surviving the Cosmos')],
      title: 'Surviving the Cosmos',
      published_on: '2024/01/11'
    )

    assert_nil match
  end

  def test_rejects_an_unrelated_episode_from_the_right_show
    match = EpisodeMatcher.best_match(
      [candidate(title: 'Ken Deutsch on municipal bonds', published_on: '2024/06/30')],
      title: 'The Fabric of Reality, with David Deutsch',
      published_on: '2024/01/11'
    )

    assert_nil match
  end

  def test_does_not_match_on_the_subject_name_alone
    match = EpisodeMatcher.best_match(
      [candidate(title: 'The Universal Constructor with David Deutsch', published_on: '2023/07/03')],
      title: 'David Deutsch Interview',
      published_on: '2021/05/20'
    )

    assert_nil match
  end

  def test_rejects_an_episode_with_no_enclosure
    match = EpisodeMatcher.best_match(
      [candidate(title: 'The Deutsch Files I', audio_url: nil)],
      title: 'The Deutsch Files I',
      published_on: '2024/01/11'
    )

    assert_nil match
  end

  def test_prefers_the_episode_published_closest_to_ours
    candidates = [
      candidate(title: 'David Deutsch returns', published_on: '2024/01/13'),
      candidate(title: 'David Deutsch returns', published_on: '2024/01/11')
    ]

    match = EpisodeMatcher.best_match(candidates, title: 'David Deutsch returns', published_on: '2024/01/11')

    assert_equal Date.parse('2024/01/11'), Date.parse(match.published_on)
  end

  def test_tolerates_a_feed_item_without_a_date
    match = EpisodeMatcher.best_match(
      [candidate(title: 'David Deutsch on the Pattern', published_on: nil)],
      title: 'David Deutsch on the Pattern',
      published_on: '2024/01/11'
    )

    refute_nil match
  end

  def test_title_similarity_ignores_punctuation_and_filler
    similarity = EpisodeMatcher.title_similarity(
      'The Universal Constructor, with David Deutsch',
      'The Universal Constructor with DAVID DEUTSCH!'
    )

    assert_in_delta 1.0, similarity, 0.001
  end

  def test_date_distance_is_nil_when_either_side_is_missing
    assert_nil EpisodeMatcher.date_distance(nil, '2024/01/11')
    assert_nil EpisodeMatcher.date_distance('2024/01/11', nil)
  end
end
