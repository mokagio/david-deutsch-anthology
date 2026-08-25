# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/duration'

class DurationTest < Minitest::Test
  def test_reads_the_three_forms_a_feed_states
    assert_equal 5034, Duration.seconds('5034')
    assert_equal 3723, Duration.seconds('62:03')
    assert_equal 3754, Duration.seconds('01:02:34')
  end

  def test_reads_a_number_as_readily_as_a_string
    assert_equal 5034, Duration.seconds(5034)
  end

  def test_rounds_a_fractional_runtime
    assert_equal 3754, Duration.seconds('3753.6')
  end

  def test_rejects_what_is_not_a_runtime
    assert_nil Duration.seconds(nil)
    assert_nil Duration.seconds('')
    assert_nil Duration.seconds('about an hour')
    assert_nil Duration.seconds('-90')
  end

  def test_rejects_a_runtime_no_episode_has
    assert_nil Duration.seconds('0')
    assert_nil Duration.seconds('42')
    assert_nil Duration.seconds('100:00:00')
  end

  def test_states_a_runtime_as_a_clock_face
    assert_equal '01:02:34', Duration.hms(3754)
    assert_equal '00:20:00', Duration.hms(1200)
    assert_nil Duration.hms(nil)
  end
end
