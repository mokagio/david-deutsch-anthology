# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/discovery'

class DiscoveryTest < Minitest::Test
  LIST = {
    'podcast_interviews' => [
      {
        'title' => 'The Deutsch Files I',
        'url' => 'https://nav.al/deutsch-files-i',
        'audio' => { 'url' => 'https://traffic.libsyn.com/naval/David_D_-_Ai.mp3' },
        'show' => { 'name' => "Naval's Podcast" },
        'published_date' => '2024/01/11'
      },
      {
        'title' => 'The Deutsch Files II',
        'url' => 'https://nav.al/deutsch-files-ii',
        'show' => { 'name' => "Naval's Podcast" },
        'published_date' => '2024/01/18'
      },
      {
        'title' => '#57 David Deutsch - The Multiverse is Real',
        'youtube_url' => 'https://www.youtube.com/watch?v=aBcDeFgHiJk',
        'show' => { 'name' => 'Within Reason Podcast' },
        'published_date' => '2024/03/05'
      }
    ],
    'talks' => [
      {
        'title' => 'Chemical scum that dream of distant quasars',
        'url' => 'https://www.ted.com/talks/david_deutsch_chemical_scum_that_dream_of_distant_quasars',
        'audio' => { 'url' => 'https://sphinx.acast.com/p/open/s/675/e/en.audio.talk.ted.com%3A47/media.mp3' },
        'show' => { 'name' => 'TED Talks Daily' },
        'delivered_date' => '2005/07/14'
      }
    ],
    'books' => [
      { 'name' => 'The Beginning of Infinity', 'urls' => [{ 'url' => 'https://www.thebeginningofinfinity.com/' }] }
    ]
  }.freeze

  def index = @index ||= Discovery::Index.new(LIST)

  def candidate(**fields)
    Discovery::Candidate.new({ title: 'David Deutsch on something new', source: 'test' }.merge(fields))
  end

  # --- URL recognition ----------------------------------------------------

  def test_recognises_the_same_url
    assert_match(/Deutsch Files I/, index.seen(candidate(url: 'https://nav.al/deutsch-files-i')))
  end

  def test_recognises_a_url_differing_only_in_www_slash_and_tracking
    seen = index.seen(candidate(url: 'https://www.nav.al/deutsch-files-i/?utm_source=twitter&si=abc'))

    assert_match(/Deutsch Files I/, seen)
  end

  def test_recognises_a_youtube_video_under_any_of_its_forms
    %w[
      https://youtu.be/aBcDeFgHiJk
      https://www.youtube.com/watch?v=aBcDeFgHiJk&list=PLxyz&t=90
      https://www.youtube.com/embed/aBcDeFgHiJk
    ].each do |url|
      refute_nil index.seen(candidate(url: url)), "expected #{url} to be recognised"
    end
  end

  def test_a_different_video_on_a_listed_channel_is_new
    assert_nil index.seen(candidate(url: 'https://www.youtube.com/watch?v=zZzZzZzZzZz'))
  end

  # --- audio recognition --------------------------------------------------

  def test_recognises_audio_served_through_a_tracking_prefix
    seen = index.seen(
      candidate(
        title: 'Something worded quite differently',
        audio_url: 'https://chrt.fm/track/ABC123/traffic.libsyn.com/naval/David_D_-_Ai.mp3'
      )
    )

    assert_match(/same audio file/, seen)
  end

  # Every TED episode's file is called `media.mp3`, so a basename alone would
  # collapse the whole show into one entry.
  def test_does_not_collapse_two_files_sharing_a_generic_basename
    assert_nil index.seen(
      candidate(
        title: 'After billions of years of monotony',
        audio_url: 'https://sphinx.acast.com/p/open/s/675/e/en.audio.talk.ted.com%3A50792/media.mp3'
      )
    )
  end

  # --- wording and date ---------------------------------------------------

  def test_recognises_the_same_episode_worded_differently_on_the_same_day
    seen = index.seen(
      candidate(title: 'David Deutsch: The Multiverse is Real', published_on: '2024/03/06')
    )

    assert_match(/Multiverse is Real/, seen)
  end

  def test_recognises_the_same_wording_under_a_different_url
    seen = index.seen(
      candidate(title: 'The Deutsch Files I', url: 'https://podcasts.apple.com/us/podcast/x/id1?i=2')
    )

    assert_match(/title matches/, seen)
  end

  def test_does_not_collapse_numbered_instalments_of_one_series
    assert_nil index.seen(
      candidate(title: 'The Deutsch Files IV', show_name: "Naval's Podcast", published_on: '2024/02/01')
    )
  end

  def test_does_not_collapse_two_appearances_on_the_same_show
    assert_nil index.seen(
      candidate(
        title: "#102 David Deutsch - You're Not Smarter Than a Caveman",
        show_name: 'Within Reason Podcast',
        published_on: '2025/04/07'
      )
    )
  end

  def test_a_genuinely_new_appearance_is_novel
    assert_nil index.seen(
      candidate(
        title: 'David Deutsch on Science, Complexity, and Explanation',
        url: "https://www.preposterousuniverse.com/podcast/2023/10/16/david-deutsch",
        show_name: "Sean Carroll's Mindscape",
        published_on: '2023/10/16'
      )
    )
  end

  # --- indexing -----------------------------------------------------------

  def test_indexes_book_urls_so_a_sweep_does_not_report_them
    refute_nil index.seen(candidate(url: 'https://thebeginningofinfinity.com'))
  end

  # A candidate sitting at a show's home page is not an episode already recorded.
  def test_does_not_index_show_urls
    assert_nil Discovery::Index.new(
      'podcast_interviews' => [{ 'title' => 'x', 'show' => { 'url' => 'https://nav.al/podcast' } }]
    ).seen(candidate(url: 'https://nav.al/podcast'))
  end

  def test_sift_separates_novel_from_known
    novel, known = Discovery.sift(
      [candidate(url: 'https://nav.al/deutsch-files-i'), candidate(url: 'https://example.com/brand-new')],
      index
    )

    assert_equal ['https://example.com/brand-new'], novel.map(&:url)
    assert_equal 1, known.size
  end

  # --- ignore rules -------------------------------------------------------

  IGNORE = {
    'shows' => [{ 'name' => "First Presbyterian Church of Pittsburgh's Podcast", 'reason' => 'A pastor.' }],
    'titles' => ['The Fabric of Reality Chapter']
  }.freeze

  def ignore = @ignore ||= Discovery::Ignore.new(IGNORE)

  def test_ignores_a_namesakes_show_and_says_why
    assert_match(/A pastor/, ignore.reject(candidate(show_name: "First Presbyterian Church of Pittsburgh's podcast")))
  end

  def test_ignores_a_commentary_title_whatever_quote_marks_it_uses
    assert_match(
      /ignored title/,
      ignore.reject(candidate(title: 'Ep 263: David Deutsch’s “The Fabric of Reality” Chapter 13'))
    )
  end

  # The point of matching titles rather than the show: Brett Hall reads the books
  # week by week and has him on now and then.
  def test_leaves_an_interview_on_a_commentary_show_alone
    assert_nil ignore.reject(candidate(title: 'Ep 100: An interview with David Deutsch', show_name: 'ToKCast'))
  end

  def test_an_empty_ignore_file_rejects_nothing
    assert_nil Discovery::Ignore.new(nil).reject(candidate(title: 'anything'))
  end

  def test_a_candidate_without_a_show_is_not_swallowed_by_a_blank_show_rule
    assert_nil Discovery::Ignore.new('shows' => [{ 'name' => nil }]).reject(candidate(show_name: nil))
  end

  # --- normalisation ------------------------------------------------------

  def test_normalize_url_ignores_non_http_urls
    assert_nil Discovery.normalize_url('mailto:someone@example.com')
    assert_nil Discovery.normalize_url(nil)
  end

  def test_normalize_url_keeps_meaningful_query_parameters
    apple = Discovery.normalize_url('https://podcasts.apple.com/us/podcast/show/id123?i=1000456')

    refute_equal apple, Discovery.normalize_url('https://podcasts.apple.com/us/podcast/show/id123?i=1000999')
  end
end
