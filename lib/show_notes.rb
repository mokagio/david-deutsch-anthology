# frozen_string_literal: true

require 'cgi/escape'

require_relative 'site'

# What a client shows underneath an episode.
#
# Written from what `list.yml` records rather than copied from the show's own
# blurb. This feed did not make the recording and has no account of it to give:
# its part is to say what the conversation is, point at where it was published,
# and name whose it remains.
module ShowNotes
  RIGHTS = 'Each episode remains the property of the show that produced it.'

  class << self
    def html(episode, site_url:)
      paragraphs = [
        "#{h episode[:label]} on <em>#{h episode[:show_name]}</em>, #{date(episode)}.",
        links(episode),
        collected(link(site_url, Site::TITLE))
      ]

      paragraphs.compact.map { |paragraph| "<p>#{paragraph}</p>" }.join("\n")
    end

    # The same episode in plain text, for `<itunes:summary>`, which Apple asks to
    # be given no markup.
    def text(episode)
      sentences = ["#{episode[:label]} on #{episode[:show_name]}, #{date(episode)}."]
      sentences << "Original: #{episode[:page_url]}" if episode[:page_url]
      sentences << collected(Site::TITLE)
      sentences.join("\n\n")
    end

    private

    def collected(title) = "Collected in #{title}. #{RIGHTS}"

    def links(episode)
      links = []
      links << link(episode[:page_url], 'Original episode') if episode[:page_url]
      links << link(episode[:show_url], episode[:show_name]) if episode[:show_url]
      links.join(' &middot; ') unless links.empty?
    end

    def link(url, text) = "<a href=\"#{h url}\">#{h text}</a>"

    def date(episode) = episode[:published_at].strftime('%-d %B %Y')

    def h(text) = CGI.escapeHTML(text.to_s)
  end
end
