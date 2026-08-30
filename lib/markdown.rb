# frozen_string_literal: true

require 'cgi/escape'

# The little of Markdown a hand-written name in `list.yml` asks for: a word or
# two of emphasis. The site has no gems, so the grammar stops where a name
# stops — inline marks, and anything else left as the literal text it was typed
# as. A link is not among the marks: a name is already the text of one, and an
# anchor cannot hold another.
module Markdown
  STRONG = /\*\*(?=\S)(.+?)(?<=\S)\*\*/
  EMPHASIS_UNDERSCORE = /(?<!\w)_(?=\S)([^_]+)(?<=\S)_(?!\w)/
  EMPHASIS_ASTERISK = /(?<!\w)\*(?=\S)([^*]+)(?<=\S)\*(?!\w)/

  class << self
    # A name's worth of Markdown as the HTML that goes inside one element.
    # Escaped before any mark is read, so text that looks like markup arrives as
    # text.
    def inline(text)
      html = CGI.escapeHTML(text.to_s.strip).gsub(/\s*\n\s*/, ' ')
      html = html.gsub(STRONG) { "<strong>#{Regexp.last_match(1)}</strong>" }
      [EMPHASIS_UNDERSCORE, EMPHASIS_ASTERISK].reduce(html) do |marked, pattern|
        marked.gsub(pattern) { "<em>#{Regexp.last_match(1)}</em>" }
      end
    end
  end
end
