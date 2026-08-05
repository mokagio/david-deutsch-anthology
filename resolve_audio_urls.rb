# frozen_string_literal: true

# Populates `audio_urls.yml`, the tracked dictionary that maps each interview's
# page URL to a playable audio file. Run it after adding entries to `list.yml`;
# `generate_podcast_rss.rb` only reads the dictionary and never hits the network.
#
#   ruby resolve_audio_urls.rb                 # resolve entries we have no answer for
#   ruby resolve_audio_urls.rb --retry-failed  # also retry the ones that came up empty
#   ruby resolve_audio_urls.rb --refresh       # re-resolve everything from scratch

require 'yaml'
require 'date'

require_relative 'lib/audio_resolver'

CACHE_PATH = 'audio_urls.yml'

refresh = ARGV.include?('--refresh')
retry_failed = ARGV.include?('--retry-failed') || refresh

cache = File.exist?(CACHE_PATH) ? YAML.load_file(CACHE_PATH) || {} : {}
interviews = YAML.load_file('list.yml', aliases: true)['podcast_interviews']
resolver = AudioResolver.new

interviews.each_with_index do |interview, index|
  url = AudioResolver.source_url(interview)
  next unless url

  cached = cache[url]
  if cached && !refresh && (cached['audio_url'] || !retry_failed)
    puts "[#{index + 1}/#{interviews.size}] cached: #{interview['title']}"
    next
  end

  puts "[#{index + 1}/#{interviews.size}] #{interview['title']}"
  result = resolver.resolve(interview)

  cache[url] = {
    'title' => interview['title'],
    'audio_url' => result.audio_url,
    'type' => result.type,
    'length' => result.length,
    'duration' => result.duration,
    'strategy' => result.strategy,
    # Feed matching is a heuristic; keeping the episode title it landed on makes a
    # bad match visible in review instead of only in a listener's player.
    'matched_title' => result.matched_title,
    'reason' => result.reason,
    'resolved_at' => Date.today.to_s
  }.compact

  puts "    #{result.reason}" unless result.resolved?

  # Written every iteration so an interrupted run keeps the answers it already paid for.
  File.write(CACHE_PATH, cache.to_yaml)
end

resolved = cache.count { |_, entry| entry['audio_url'] }
puts
puts "#{resolved}/#{cache.size} entries have audio. Dictionary written to #{CACHE_PATH}."
