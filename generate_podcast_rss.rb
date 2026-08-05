# frozen_string_literal: true

# Builds the podcast feed from `list.yml` plus the audio dictionary in
# `audio_urls.yml`. Deliberately offline: an interview only reaches the feed once
# `resolve_audio_urls.rb` has found a playable file for it, because a podcast item
# without an enclosure is invisible to every podcast client.

require 'yaml'
require 'erb'
require 'time'
require 'cgi'
require 'fileutils'

SITE_URL = 'https://mokagio.github.io/david-deutsch-anthology/'
FEED_TITLE = 'David Deutsch Podcast Interviews'
FEED_DESCRIPTION = 'A collection of podcast appearances by David Deutsch.'
FEED_AUTHOR = 'David Deutsch'

def h(text) = CGI.escapeHTML(text.to_s)

interviews = YAML.load_file('list.yml', aliases: true)['podcast_interviews']
audio = File.exist?('audio_urls.yml') ? YAML.load_file('audio_urls.yml') || {} : {}

skipped = []

episodes = interviews.filter_map do |interview|
  source_url = interview['podcast_url'] || interview['url'] || interview['youtube_url']
  entry = audio[source_url]

  unless entry && entry['audio_url']
    skipped << [interview['title'], entry&.fetch('reason', nil) || 'not resolved yet']
    next
  end

  show_name = interview.dig('show', 'name') || 'Unknown Show'

  {
    title: interview['title'],
    page_url: source_url,
    guid: source_url,
    published_at: Time.parse(interview['published_date']),
    description: "Interview on #{show_name}",
    show_name: show_name,
    audio_url: entry['audio_url'],
    type: entry['type'] || 'audio/mpeg',
    length: entry['length'].to_i,
    duration: entry['duration']
  }
end.sort_by { |episode| episode[:published_at] }.reverse

# A conversation listed twice — say, once as the host's video and once as the
# show's episode — resolves to one file, and a client would offer it twice.
episodes = episodes.uniq { |episode| episode[:audio_url] }

abort 'No episodes have audio yet — run `ruby resolve_audio_urls.rb` first.' if episodes.empty?

output_path = File.join('public', 'podcast.rss')
FileUtils.mkdir_p(File.dirname(output_path))

feed_url = File.join(SITE_URL, File.basename(output_path))
feed_title = FEED_TITLE
feed_description = FEED_DESCRIPTION
feed_author = FEED_AUTHOR
site_url = SITE_URL
# Derived from the newest episode rather than the clock, so regenerating without
# a content change produces an identical file.
build_date = episodes.first[:published_at]

template = ERB.new(File.read(File.join('templates', 'rss_feed.erb')), trim_mode: '-')
File.write(output_path, template.result(binding))

puts "RSS feed generated: #{output_path} (#{episodes.size} episodes)"

return if skipped.empty?

puts "\nSkipped #{skipped.size} entries with no audio:"
skipped.each { |title, reason| puts "  - #{title} (#{reason})" }
