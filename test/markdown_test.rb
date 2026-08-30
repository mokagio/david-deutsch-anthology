# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/markdown'

class MarkdownTest < Minitest::Test
  def test_renders_emphasis_and_strength
    assert_equal '<em>quite</em> so', Markdown.inline('_quite_ so')
    assert_equal '<em>quite</em> so', Markdown.inline('*quite* so')
    assert_equal '<strong>quite</strong> so', Markdown.inline('**quite** so')
  end

  def test_marks_more_than_one_run_of_emphasis
    assert_equal '<em>A Title</em> with <em>transcripts</em>', Markdown.inline('_A Title_ with _transcripts_')
  end

  def test_leaves_an_underscore_inside_a_word_alone
    assert_equal 'read published_date and published_at', Markdown.inline('read published_date and published_at')
  end

  def test_escapes_text_that_looks_like_markup
    assert_equal '&lt;script&gt;alert(1)&lt;/script&gt;', Markdown.inline('<script>alert(1)</script>')
  end

  def test_leaves_a_link_as_typed
    assert_equal(
      '[A page](https://example.com/a-page)',
      Markdown.inline('[A page](https://example.com/a-page)')
    )
  end

  def test_leaves_an_unclosed_mark_as_typed
    assert_equal 'a * b', Markdown.inline('a * b')
    assert_equal '_almost', Markdown.inline('_almost')
  end

  def test_reads_a_wrapped_paragraph_as_one_line
    assert_equal 'one two three', Markdown.inline("one\n  two\nthree\n")
  end
end
