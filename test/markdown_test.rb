# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/markdown'

class MarkdownTest < Minitest::Test
  def test_renders_a_link
    assert_equal(
      '<a href="https://example.com/a-page" target="_blank">A page</a> is worth a look',
      Markdown.inline('[A page](https://example.com/a-page) is worth a look')
    )
  end

  def test_keeps_a_query_string_in_the_href
    assert_equal(
      '<a href="https://example.com/?a=1&amp;b=2" target="_blank">Both</a>',
      Markdown.inline('[Both](https://example.com/?a=1&b=2)')
    )
  end

  def test_renders_emphasis_and_strength
    assert_equal '<em>quite</em> so', Markdown.inline('_quite_ so')
    assert_equal '<em>quite</em> so', Markdown.inline('*quite* so')
    assert_equal '<strong>quite</strong> so', Markdown.inline('**quite** so')
  end

  def test_marks_emphasis_inside_a_link
    assert_equal(
      '<a href="https://book.example" target="_blank"><em>A Title</em></a> by an author',
      Markdown.inline('[_A Title_](https://book.example) by an author')
    )
  end

  def test_wraps_a_link_when_asked_for_a_class
    assert_equal(
      '<span class="accent-link"><a href="https://a.example" target="_blank">A</a></span> and so on',
      Markdown.inline('[A](https://a.example) and so on', link_class: 'accent-link')
    )
  end

  def test_leaves_an_underscore_inside_a_word_alone
    assert_equal 'read published_date and published_at', Markdown.inline('read published_date and published_at')
  end

  def test_escapes_text_that_looks_like_markup
    assert_equal '&lt;script&gt;alert(1)&lt;/script&gt;', Markdown.inline('<script>alert(1)</script>')
  end

  def test_leaves_an_unclosed_mark_as_typed
    assert_equal '[A page](https', Markdown.inline('[A page](https')
    assert_equal 'a * b', Markdown.inline('a * b')
  end

  def test_reads_a_wrapped_paragraph_as_one_line
    assert_equal 'one two three', Markdown.inline("one\n  two\nthree\n")
  end

  def test_marks_more_than_one_link_in_a_line
    assert_equal(
      '<a href="https://a.example" target="_blank">A</a> and <a href="https://b.example" target="_blank">B</a>',
      Markdown.inline('[A](https://a.example) and [B](https://b.example)')
    )
  end
end
