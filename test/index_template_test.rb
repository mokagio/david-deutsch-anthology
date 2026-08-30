# frozen_string_literal: true

require 'erb'
require 'date'
require 'minitest/autorun'

require_relative '../lib/markdown'
require_relative '../lib/site'

class IndexTemplateTest < Minitest::Test
  TEMPLATE = ERB.new(File.read(File.expand_path('../templates/index.erb', __dir__)))

  def render(interviews, other: [])
    books = []
    talks = []
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

    refute_includes html, 'data-version='
    assert_includes html, '<a class="episode-name" href="https://episode.example" target="_blank">An interview</a>'
    assert_equal 1, html.scan('<a href="https://episode.example" target="_blank">Website</a>').size
    assert_equal 1, html.scan('27th Aug 2026').size
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
    assert_includes html, '<a class="episode-name" href="https://youtube.example/watch" target="_blank">An interview</a>'
    assert_equal 1, html.scan('>YouTube</a>').size
    assert_equal 1, html.scan('>Podcast</a>').size
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

      assert_equal 1, render(entry).scan(displayed).size
    end
  end

  def test_renders_the_full_interview_list
    entries = 9.times.map do |index|
      interview(podcast_url: "https://podcast.example/#{index}").merge('title' => "Episode #{index + 1}")
    end
    html = render(entries)

    assert_equal 1, html.scan('Episode 8').size
    assert_equal 1, html.scan('Episode 9').size
  end

  def test_all_visible_collections_share_the_list_style
    html = render(interview(podcast_url: 'https://podcast.example/episode'))

    assert_equal 3, html.scan(/<ul class="[^"]*anthology-list/).size
  end

  def test_book_and_other_titles_use_the_podcast_title_interaction
    books = [{ 'name' => 'A Book', 'published_year' => 2026,
               'urls' => [{ 'url' => 'https://book.example' }] }]
    other = [{ 'name' => 'Another resource', 'url' => 'https://other.example', 'published_year' => 1992 }]
    talks = []
    podcast_interviews = [interview(podcast_url: 'https://podcast.example/episode')]
    html = TEMPLATE.result(binding)

    assert_includes html, '<a class="anthology-link" href="https://book.example"'
    assert_includes html, ' · <span class="episode-date">2026</span>'
    assert_includes html, '<a class="anthology-link" href="https://other.example"'
    assert_includes html, 'Another resource</a> · <span class="episode-date">1992</span>'
  end

  def test_other_items_omit_the_date_separator_without_a_year
    books = []
    other = [{ 'name' => 'Undated resource', 'url' => 'https://other.example' }]
    talks = []
    podcast_interviews = [interview(podcast_url: 'https://podcast.example/episode')]

    refute_includes TEMPLATE.result(binding), 'Undated resource</a> ·'
  end

  def test_page_loads_the_cosmic_background
    html = render(interview(podcast_url: 'https://podcast.example/episode'))

    refute_includes html, '<select id="background-mode">'
    assert_includes html, '<canvas id="cosmic-background"'
    assert_includes html, '<script src="cosmic-backgrounds.js"></script>'
  end

  def test_states_what_a_link_preview_needs
    html = render(interview(podcast_url: 'https://podcast.example/episode'))

    assert_includes html, '<meta property="og:title" content="The David Deutsch Anthology">'
    assert_includes html, %(<meta property="og:description" content="#{Site::DESCRIPTION}">)
    assert_includes html, '<meta property="og:url" content="https://mokagio.github.io/david-deutsch-anthology/">'
    assert_includes html, %(<meta name="description" content="#{Site::DESCRIPTION}">)
    assert_includes html, '<meta property="og:type" content="website">'
  end

  # Slack lays a preview out from the stated size, and drops a picture it cannot
  # fit the card: a square one is what unfurled with a title and no image.
  def test_previews_with_the_card_at_its_measured_size
    html = render(interview(podcast_url: 'https://podcast.example/episode'))

    assert_includes html, '<meta property="og:image" content="https://mokagio.github.io/david-deutsch-anthology/og-card.jpg">'
    assert_includes html, '<meta property="og:image:width" content="1200">'
    assert_includes html, '<meta property="og:image:height" content="630">'
    assert_includes html, '<meta name="twitter:card" content="summary_large_image">'
  end

  def test_intro_links_are_styled_without_a_layout_wrapper
    html = render(interview(podcast_url: 'https://podcast.example/episode'))

    assert_equal 3, html.scan('class="intro-link"').size
    refute_includes html, '<div class="intro">'
  end

  def test_lists_a_named_other_entry_as_a_link
    html = render(
      interview(podcast_url: 'https://podcast.example/episode'),
      other: [{ 'name' => 'A documentary', 'url' => 'https://video.example', 'published_year' => 1992 }]
    )

    assert_includes html, '<a class="anthology-link" href="https://video.example" target="_blank">A documentary</a>'
    assert_includes html, '<span class="episode-date">1992</span>'
  end

  def test_marks_up_an_other_entry_name_written_in_markdown
    html = render(
      interview(podcast_url: 'https://podcast.example/episode'),
      other: [{ 'name' => '_A collection_ with _transcripts_', 'url' => 'https://collection.example' }]
    )

    assert_includes(
      html,
      '<a class="anthology-link" href="https://collection.example" target="_blank">' \
      '<em>A collection</em> with <em>transcripts</em></a>'
    )
  end
end
