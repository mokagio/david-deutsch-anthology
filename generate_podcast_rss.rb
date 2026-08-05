# frozen_string_literal: true

# Builds the podcast feed from `list.yml` plus the audio dictionary in
# `audio_urls.yml`.
#
# An interview the dictionary has never seen is resolved on the spot, so an entry
# added to `list.yml` reaches the feed even if nobody ran `resolve_audio_urls.rb`
# first. Entries the dictionary already answered — including the ones it could
# find no audio for — are taken at their word, which keeps a normal build offline.
#
#   ruby generate_podcast_rss.rb            # resolve entries the dictionary lacks
#   ruby generate_podcast_rss.rb --offline  # build from the dictionary alone

require 'yaml'
require 'erb'
require 'cgi'
require 'fileutils'

require_relative 'lib/audio_dictionary'
require_relative 'lib/audio_resolver'
require_relative 'lib/feed_builder'

SITE_URL = 'https://mokagio.github.io/david-deutsch-anthology/'
FEED_TITLE = 'David Deutsch Podcast Interviews'
FEED_DESCRIPTION = 'A collection of podcast appearances by David Deutsch.'
FEED_AUTHOR = 'David Deutsch'

def h(text) = CGI.escapeHTML(text.to_s)

offline = ARGV.include?('--offline')

interviews = YAML.load_file('list.yml', aliases: true)['podcast_interviews']
dictionary = AudioDictionary.new

unless offline
  resolver = AudioResolver.new
  missing = interviews.reject { |interview| dictionary.known?(AudioResolver.source_url(interview)) }

  puts "Resolving #{missing.size} entries missing from the dictionary..." unless missing.empty?
  missing.each do |interview|
    puts "  #{interview['title']}"
    dictionary.record(interview, resolver.resolve(interview))
  end

  puts "Dictionary updated — commit #{AudioDictionary::DEFAULT_PATH}." if dictionary.save
end

build = FeedBuilder.build(interviews, dictionary)
abort 'No episodes have audio yet — run `ruby resolve_audio_urls.rb` first.' if build.episodes.empty?

output_path = File.join('public', 'podcast.rss')
FileUtils.mkdir_p(File.dirname(output_path))

episodes = build.episodes
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

return if build.skipped.empty?

puts "\nSkipped #{build.skipped.size} entries with no audio:"
build.skipped.each { |skip| puts "  - #{skip.title} (#{skip.reason})" }
