# frozen_string_literal: true

# Given a URL for a David Deutsch podcast appearance, works out everything
# `list.yml` records about it and prints the entry, ready to paste.
#
# Prints rather than writes: where the entry belongs depends on publication date,
# and whether the show already has a YAML anchor is a judgement the caller makes.
#
#   ruby .claude/skills/add-entry/scripts/entry_fields.rb <url> [--feed URL] [--show NAME] [--title TITLE]
#
# See docs/audio-sourcing.md for why each step is the way it is.

require 'cgi'
require 'json'
require 'rss'
require 'uri'
require 'yaml'

ROOT = File.expand_path('../../../..', __dir__)
require File.join(ROOT, 'lib', 'http_client')
require File.join(ROOT, 'lib', 'enclosure')

def option(flag) = ARGV.include?(flag) ? ARGV[ARGV.index(flag) + 1] : nil

source_url = ARGV.first
abort 'usage: entry_fields.rb <url> [--feed URL] [--show NAME] [--title TITLE]' unless source_url && !source_url.start_with?('--')

APPLE = %r{podcasts\.apple\.com/.*?/id(?<collection>\d+)}
STOP_WORDS = %w[a an the with and or of on in to for at by is it from ep episode part].freeze

def tokenize(text) = text.to_s.downcase.gsub(/[^a-z0-9\s]/, ' ').split - STOP_WORDS

def similarity(one, other)
  left = tokenize(one)
  right = tokenize(other)
  return 0.0 if left.empty? || right.empty?

  (2.0 * (left & right).size) / (left.size + right.size)
end

def meta_content(body, property)
  tag = body.to_s.scan(/<meta[^>]+>/i).find { |m| m.match?(/(?:property|name)=["']#{property}["']/i) }
  tag && CGI.unescapeHTML(tag[/content=["']([^"']*)["']/i, 1].to_s)
end

def itunes_get(url)
  response = HttpClient.get(url)
  response ? JSON.parse(response.body)['results'] || [] : []
rescue JSON::ParserError
  []
end

apple = APPLE.match(source_url)
page = ''
final_url = source_url
episode_title = option('--title')
feed_url = option('--feed')

if apple
  # Apple serves the API happily and the web page not at all, so never fetch the page.
  results = itunes_get("https://itunes.apple.com/lookup?id=#{apple[:collection]}&entity=podcastEpisode&limit=200")
  feed_url ||= results.filter_map { |r| r['feedUrl'] }.first
  wanted = source_url[/[?&]i=(\d+)/, 1]
  episode_title ||= results.find { |r| r['trackId'].to_s == wanted }&.fetch('trackName', nil)
else
  # An aggregator page is worth its title and nothing else: it embeds several
  # episodes' audio, so the file has to come from the show's own feed.
  response = HttpClient.get(source_url)
  abort "could not fetch #{source_url} — pass --title and --feed" unless response || (episode_title && feed_url)

  if response
    page = response.body
    final_url = response.url
    episode_title ||= meta_content(page, 'og:title') || page[%r{<title[^>]*>(.*?)</title>}mi, 1]&.strip
  end
end

abort 'could not determine the episode title; pass --title' unless episode_title
warn "episode  : #{episode_title}"
warn "resolved : #{final_url}" unless final_url == source_url

feed_url ||= page.scan(/<link[^>]+>/i)
                 .select { |tag| tag.match?(%r{type=["']application/rss\+xml["']}i) }
                 .filter_map { |tag| tag[/href=["']([^"']+)["']/i, 1] }
                 .reject { |href| href.include?('comments') }
                 .map { |href| URI.join(final_url, CGI.unescapeHTML(href)).to_s }
                 .first

# Last resort, and the least reliable: search by show name. A slug in the
# aggregator's URL is usually a better query than anything on the page.
if feed_url.nil?
  show_query = option('--show') || final_url[%r{/podcast/([^/]+)/}, 1]&.tr('-', ' ')
  abort 'could not find a feed; pass --feed or --show' unless show_query

  warn "searching : #{show_query}"
  feed_url = itunes_get("https://itunes.apple.com/search?term=#{CGI.escape(show_query)}&entity=podcast&limit=3")
             .filter_map { |r| r['feedUrl'] }.first
end

abort 'could not find a feed; pass --feed' unless feed_url
warn "feed     : #{feed_url}"

feed_body = HttpClient.get(feed_url)
abort "could not read feed #{feed_url}" unless feed_body

feed = RSS::Parser.parse(feed_body.body, false)
abort 'feed did not parse' unless feed

scored = feed.items.filter_map do |item|
  title = item.title.respond_to?(:content) ? item.title.content : item.title
  next unless item.respond_to?(:enclosure) && item.enclosure&.url

  [item, title.to_s.strip, similarity(title, episode_title)]
end

item, matched_title, score = scored.max_by(&:last)
abort 'no episode in that feed has an enclosure' unless item

warn format('matched  : %s (%.2f)', matched_title, score)
warn 'WARNING: weak title match — confirm this is the right episode' if score < 0.6

# A feed that says `length="0"` is Megaphone being Megaphone. Ask the file.
declared = item.enclosure.length.to_i
details = declared.positive? ? nil : Enclosure.probe(item.enclosure.url)
length = declared.positive? ? declared : details&.length
type = item.enclosure.type || details&.type || Enclosure.mime_type_for(item.enclosure.url)

warn 'NOTE: feed declared length=0, probed the file instead' unless declared.positive?
warn 'WARNING: could not determine a byte length — the episode cannot enter the feed' unless length.to_i.positive?

published = item.pubDate
show_name = (feed.channel.title.respond_to?(:content) ? feed.channel.title.content : feed.channel.title).to_s.strip
show_url = feed.channel.link.to_s.strip

# An aggregator link gives no hint that the episode is already in the list under
# its own site's URL, and the audio file is the only reliable way to tell.
existing = YAML.load_file(File.join(ROOT, 'list.yml'), aliases: true)['podcast_interviews'].find do |entry|
  [entry['audio_url'], entry['url'], entry['podcast_url'], entry['youtube_url']].compact.any? do |recorded|
    recorded == item.enclosure.url || recorded == source_url
  end
end

if existing
  warn ''
  warn "ALREADY IN THE LIST: #{existing['title']} (#{existing['published_date']}, #{existing.dig('show', 'name')})"
  warn 'Adding this would publish the same recording twice. Stop unless you know better.'
end

quoted = matched_title.match?(/[:#]/) ? matched_title.inspect : matched_title

puts <<~YAML
    - title: #{quoted}
      podcast_url: #{source_url}
      audio_url: #{item.enclosure.url}
      audio_type: #{type}
      audio_length: #{length}
      show:
        name: #{show_name}
        url: #{show_url}
      published_date: #{published&.strftime('%Y/%m/%d')}
YAML

warn ''
warn "duration : #{(item.itunes_duration&.content rescue nil)} (compare against any video release before adding youtube_url)"
