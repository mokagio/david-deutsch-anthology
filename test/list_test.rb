# frozen_string_literal: true

require 'minitest/autorun'
require 'yaml'

require_relative '../lib/episode_title'

# The conventions `list.yml` holds to, checked against the list itself, so a new
# entry that breaks one fails the build rather than waiting to be noticed.
class ListTest < Minitest::Test
  LIST = YAML.load_file(File.expand_path('../list.yml', __dir__), aliases: true)

  def titles
    LIST.each_value.select { |entries| entries.is_a?(Array) }.flat_map do |entries|
      entries.filter_map { |entry| entry['title'] if entry.is_a?(Hash) }
    end
  end

  def test_no_title_carries_the_show_episode_number
    numbered = titles.select { |title| EpisodeTitle.numbered?(title) }

    assert_empty numbered, "titles keep the show's numbering: #{numbered.join(', ')}"
  end
end
