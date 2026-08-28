# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/build_date'

class BuildDateTest < Minitest::Test
  def test_dates_the_feed_by_the_last_commit
    committed = Time.utc(2026, 8, 25, 9, 30, 0)

    assert_equal committed, BuildDate.current(head: -> { committed })
  end

  def test_falls_back_to_the_clock_without_a_repository
    before = Time.now.utc

    assert_operator BuildDate.current(head: -> { nil }), :>=, before
  end

  def test_reads_the_repository_it_is_built_from
    assert_kind_of Time, BuildDate.head_commit
  end
end
