# frozen_string_literal: true

require 'minitest/autorun'
require 'time'

require_relative '../lib/show_notes'

class ShowNotesTest < Minitest::Test
  SITE = 'https://example.com/anthology/'

  def episode(**overrides)
    {
      label: 'Interview', show_name: 'EconTalk', show_url: 'https://econtalk.org',
      origin_url: 'https://econtalk.org/deutsch', published_at: Time.parse('2024/01/11')
    }.merge(overrides)
  end

  def test_says_what_the_recording_is_and_when
    assert_includes ShowNotes.html(episode, site_url: SITE),
                    '<p>Interview on <em>EconTalk</em>, 11 January 2024.</p>'
  end

  def test_calls_a_talk_a_talk
    assert_includes ShowNotes.html(episode(label: 'Talk'), site_url: SITE), '<p>Talk on <em>EconTalk</em>'
  end

  def test_links_the_episode_and_the_show
    notes = ShowNotes.html(episode, site_url: SITE)

    assert_includes notes, '<a href="https://econtalk.org/deutsch">Original episode</a>'
    assert_includes notes, '<a href="https://econtalk.org">EconTalk</a>'
  end

  def test_links_the_anthology_and_names_whose_the_episode_is
    notes = ShowNotes.html(episode, site_url: SITE)

    assert_includes notes, "<a href=\"#{SITE}\">David Deutsch Anthology</a>"
    assert_includes notes, ShowNotes::RIGHTS
  end

  def test_leaves_out_a_link_the_entry_does_not_have
    notes = ShowNotes.html(episode(show_url: nil), site_url: SITE)

    refute_includes notes, '&middot;'
    assert_includes notes, 'Original episode'
  end

  def test_writes_no_empty_paragraph_when_there_is_nothing_to_link
    notes = ShowNotes.html(episode(show_url: nil, origin_url: nil), site_url: SITE)

    refute_includes notes, '<p></p>'
  end

  def test_escapes_what_a_show_calls_itself
    notes = ShowNotes.html(episode(show_name: 'Ben & Jerry <live>'), site_url: SITE)

    assert_includes notes, '<em>Ben &amp; Jerry &lt;live&gt;</em>'
  end

  def test_summarises_without_markup
    text = ShowNotes.text(episode)

    assert_includes text, 'Interview on EconTalk, 11 January 2024.'
    assert_includes text, 'Original: https://econtalk.org/deutsch'
    refute_match(/<[a-z]/, text)
  end
end
