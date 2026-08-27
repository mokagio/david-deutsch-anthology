# frozen_string_literal: true

require 'erb'
require 'date'
require 'minitest/autorun'

class IndexTemplateTest < Minitest::Test
  TEMPLATE = ERB.new(File.read(File.expand_path('../templates/index.erb', __dir__)))

  def render(interviews)
    books = []
    talks = []
    other = []
    podcast_interviews = interviews.is_a?(Array) ? interviews : [interviews]

    TEMPLATE.result(binding)
  end

  def interview(**urls)
    {
      'title' => 'An interview',
      'show' => { 'name' => 'A Show', 'url' => 'https://show.example' },
      'published_date' => '2026/08/27'
    }.merge(urls.transform_keys(&:to_s))
  end

  def test_lists_every_source_in_a_fixed_order
    html = render(
      interview(
        url: 'https://episode.example',
        youtube_url: 'https://youtube.example/watch',
        podcast_url: 'https://podcast.example/episode'
      )
    )

    assert_equal 10, html.scan(/data-version="\d+"/).size
    assert_equal 10, html.scan('<a href="https://episode.example" target="_blank">Website</a>').size
    assert_equal 10, html.scan('27th Aug 2026').size
    refute_includes html, '<a href="https://show.example"'
  end

  def test_omits_sources_the_entry_does_not_have
    html = render(
      interview(
        youtube_url: 'https://youtube.example/watch',
        podcast_url: 'https://podcast.example/episode'
      )
    )

    assert_equal 0, html.scan('>Website</a>').size
    assert_equal 10, html.scan('>YouTube</a>').size
    assert_equal 10, html.scan('>Podcast</a>').size
  end

  def test_uses_english_ordinal_date_suffixes
    dates = {
      '2026/08/01' => '1st Aug 2026',
      '2026/08/02' => '2nd Aug 2026',
      '2026/08/03' => '3rd Aug 2026',
      '2026/08/11' => '11th Aug 2026',
      '2026/08/12' => '12th Aug 2026',
      '2026/08/13' => '13th Aug 2026',
      '2026/08/21' => '21st Aug 2026'
    }

    dates.each do |stored, displayed|
      entry = interview(podcast_url: 'https://podcast.example/episode')
      entry['published_date'] = stored

      assert_equal 10, render(entry).scan(displayed).size
    end
  end

  def test_every_version_uses_only_the_first_eight_entries
    entries = 9.times.map do |index|
      interview(podcast_url: "https://podcast.example/#{index}").merge('title' => "Episode #{index + 1}")
    end
    html = render(entries)

    assert_equal 10, html.scan('Episode 8').size
    refute_includes html, 'Episode 9'
  end
end
