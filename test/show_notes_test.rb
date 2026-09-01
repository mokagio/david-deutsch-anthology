# frozen_string_literal: true
require 'minitest/autorun'
require 'time'
require_relative '../lib/show_notes'
class ShowNotesTest < Minitest::Test
  SITE = 'https://example.com/anthology/'
  LINK = "<a href=\"#{SITE}\">"
  SHOW = 'https://econtalk.org'
  def ep(**o)
    { label: 'Interview', show_name: 'EconTalk', show_url: SHOW,
      page_url: "#{SHOW}/deutsch", published_at: Time.parse('2024/01/11') }.merge(o)
  end
  def test_what_and_when
    assert_includes ShowNotes.html(ep, site_url: SITE),
                    '<p>Interview on <em>EconTalk</em>, 11 January 2024.</p>'
  end
  def test_calls_a_talk_a_talk
    assert_includes ShowNotes.html(ep(label: 'Talk'), site_url: SITE), '<p>Talk on <em>EconTalk</em>'
  end
  def test_links_episode_and_show
    n = ShowNotes.html(ep, site_url: SITE)
    assert_includes n, "<a href=\"#{SHOW}/deutsch\">Original episode</a>"
    assert_includes n, "<a href=\"#{SHOW}\">EconTalk</a>"
  end
  def test_links_anthology
    n = ShowNotes.html(ep, site_url: SITE)
    assert_includes n, "#{LINK}#{ShowNotes::NAME}</a>"
    refute_includes n, "the #{LINK}"
    assert_includes n, ShowNotes::RIGHTS
  end
  def test_omits_absent_link
    n = ShowNotes.html(ep(show_url: nil), site_url: SITE)
    refute_includes n, '&middot;'
    assert_includes n, 'Original episode'
  end
  def test_writes_no_empty_paragraph
    n = ShowNotes.html(ep(show_url: nil, page_url: nil), site_url: SITE)
    refute_includes n, '<p></p>'
  end
  def test_escapes_show_name
    n = ShowNotes.html(ep(show_name: 'Ben & Jerry <live>'), site_url: SITE)
    assert_includes n, '<em>Ben &amp; Jerry &lt;live&gt;</em>'
  end
  def test_summary_plain
    text = ShowNotes.text(ep)
    assert_includes text, 'Interview on EconTalk, 11 January 2024.'
    assert_includes text, "Original: #{SHOW}/deutsch"
    assert_includes text, "Collected in #{ShowNotes::NAME}."
    refute_match(/<[a-z]/, text)
  end
end
