# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/episode_title'

class EpisodeTitleTest < Minitest::Test
  def test_strips_the_forms_a_show_numbers_with
    {
      '#4 - Decisions' => 'Decisions',
      '#-1 - AGI (with David Deutsch)' => 'AGI (with David Deutsch)',
      'Ep 223: The Deutsch Files IV' => 'The Deutsch Files IV',
      'Episode 100 — The Beginning of Infinity' => 'The Beginning of Infinity',
      '#5 The Art of Decision Making' => 'The Art of Decision Making'
    }.each { |numbered, bare| assert_equal bare, EpisodeTitle.strip_numbering(numbered) }
  end

  def test_leaves_a_title_that_merely_starts_with_a_number
    ['2001: A Space Odyssey', '10 questions for David Deutsch', 'The Deutsch Files I'].each do |title|
      refute EpisodeTitle.numbered?(title)
      assert_equal title, EpisodeTitle.strip_numbering(title)
    end
  end
end
