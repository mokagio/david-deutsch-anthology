# frozen_string_literal: true

# Builds the podcast feed from `list.yml`, which is the source of truth for which
# interviews have audio.
#
# An interview with no `audio` is resolved on the spot, so an entry added to
# the list reaches the feed before anyone has run `/audit-list` to record its
# audio. Nothing is written back — recording a resolution in `list.yml` is that
# skill's job, and a build has no business editing the source of truth.
#
# An `<enclosure>` has to state the file's MIME type and byte length, so an entry
# whose `audio` block records neither is probed for both.
#
#   ruby bin/generate_podcast_rss.rb               # resolve entries with no audio
#   ruby bin/generate_podcast_rss.rb --no-resolve  # use only what the list records

require 'yaml'
require 'erb'
require 'cgi/escape'
require 'fileutils'

require_relative '../lib/assets'
require_relative '../lib/cover'
require_relative '../lib/media_resolver'
require_relative '../lib/feed_builder'
require_relative '../lib/show_notes'

SITE_URL = 'https://mokagio.github.io/david-deutsch-anthology/'
FEED_TITLE = 'David Deutsch Podcast Interviews'
FEED_DESCRIPTION = 'A collection of podcast appearances by David Deutsch.'
FEED_AUTHOR = 'David Deutsch'

def h(text) = CGI.escapeHTML(text.to_s)

def cdata(markup) = "<![CDATA[#{markup.gsub(']]>', ']]]]><![CDATA[>')}]]>"

resolve_missing = !ARGV.include?('--no-resolve')

list = YAML.load_file('list.yml', aliases: true)
interviews = list['podcast_interviews']

if resolve_missing
  pending = interviews.reject { |interview| interview.dig('audio', 'url') }

  unless pending.empty?
    puts "Looking for audio for #{pending.size} interviews the list does not record..."
    resolver = MediaResolver.new(logger: ->(message) { puts message })

    found = pending.count do |interview|
      result = resolver.resolve(interview)
      (interview['audio'] ||= {})['url'] = result.audio_url if result.resolved?
      result.resolved?
    end

    puts "Found #{found}. Run `/audit-list` to record them in list.yml." if found.positive?
  end
end

build = FeedBuilder.build(list)
abort 'Nothing in list.yml has usable audio.' if build.episodes.empty?

output_path = File.join('public', 'podcast.rss')
FileUtils.mkdir_p(File.dirname(output_path))

cover = Cover::PATHS.find { |candidate| File.exist?(candidate) }
cover_errors = cover ? Cover.errors(cover) : []
abort "The channel artwork will not do:\n  #{cover_errors.join("\n  ")}" unless cover_errors.empty?

Assets.publish(into: 'public')
feed_image_url = cover ? File.join(SITE_URL, File.basename(cover)) : nil
puts "No channel artwork: drop a square JPEG or PNG at #{Cover::PATHS.first}." unless cover

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

puts "\nSkipped #{build.skipped.size} entries:"
build.skipped.each { |skip| puts "  - #{skip.title} (#{skip.reason})" }
