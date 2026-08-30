# frozen_string_literal: true

require 'cgi/escape'

# The little of Markdown a hand-written line in `list.yml` asks for: a link, a
# word or two of emphasis. The site has no gems, so the grammar stops where a
# sentence stops — one paragraph, inline marks, and anything else left as the
# literal text it was typed as.
module Markdown
  LINK = /\[([^\]]+)\]\(([^)\s]+)\)/
  STRONG = /\*\*(?=\S)(.+?)(?<=\S)\*\*/
  EMPHASIS_UNDERSCORE = /(?<!\w)_(?=\S)([^_]+)(?<=\S)_(?!\w)/
  EMPHASIS_ASTERISK = /(?<!\w)\*(?=\S)([^*]+)(?<=\S)\*(?!\w)/

  class << self
    # A paragraph's worth of Markdown as the HTML that goes inside one element.
    # Escaped before any mark is read, so text that looks like markup arrives as
    # text and a `&` in a URL survives into the href.
    #
    # `link_class` names an element wrapped around each anchor rather than a
    # class set on it: a colour Chrome derives from a custom property is dropped
    # once the link has been visited, and only an inherited one survives.
    def inline(text, link_class: nil)
      html = CGI.escapeHTML(text.to_s.strip).gsub(/\s*\n\s*/, ' ')
      html = html.gsub(LINK) { link(Regexp.last_match(2), Regexp.last_match(1), link_class) }
      html = html.gsub(STRONG) { "<strong>#{Regexp.last_match(1)}</strong>" }
      [EMPHASIS_UNDERSCORE, EMPHASIS_ASTERISK].reduce(html) do |marked, pattern|
        marked.gsub(pattern) { "<em>#{Regexp.last_match(1)}</em>" }
      end
    end

    private

    def link(url, text, link_class)
      anchor = "<a href=\"#{url}\" target=\"_blank\">#{text}</a>"
      link_class ? "<span class=\"#{link_class}\">#{anchor}</span>" : anchor
    end
  end
end
