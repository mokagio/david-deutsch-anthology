# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/published_at'

class PublishedAtTest < Minitest::Test
  def test_gives_a_bare_day_midday_utc
    stamp = PublishedAt.parse('2026/02/12')

    assert_equal Time.utc(2026, 2, 12, 12, 0, 0), stamp
    assert_equal 'Thu, 12 Feb 2026 12:00:00 +0000', stamp.rfc2822
  end

  def test_reads_a_day_written_either_way
    assert_equal PublishedAt.parse('2026/02/12'), PublishedAt.parse('2026-02-12')
  end

  # Midnight is the recorded day only east of Greenwich; midday is it everywhere
  # from UTC-12 to UTC+11.
  def test_holds_the_recorded_day_across_the_zones_a_listener_reads_it_in
    stamp = PublishedAt.parse('2026/02/12')

    assert_equal 12, stamp.getlocal('-11:00').day
    assert_equal 12, stamp.getlocal('+11:00').day
  end

  # The offset a source feed states is presentation; the instant it names is not.
  def test_reads_a_stated_instant_whatever_zone_it_names_it_in
    assert_equal Time.utc(2026, 2, 12, 9, 30, 0), PublishedAt.parse('2026-02-12T20:30:00+11:00')
    assert_equal Time.utc(2026, 2, 12, 9, 30, 0), PublishedAt.parse('Thu, 12 Feb 2026 09:30:00 GMT')
    assert_equal 0, PublishedAt.parse('2026-02-12T20:30:00+11:00').utc_offset
  end

  def test_reads_an_instant_stated_without_a_zone_as_utc
    stamp = PublishedAt.parse('2026-02-12 09:30:00')

    assert_equal Time.utc(2026, 2, 12, 9, 30, 0), stamp
    assert_equal 0, stamp.utc_offset
  end
end
