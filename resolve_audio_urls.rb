# frozen_string_literal: true

# Fills in `audio_urls.yml`, the tracked dictionary mapping each interview's page
# URL to a playable audio file.
#
# `generate_podcast_rss.rb` resolves entries the dictionary has never seen, so
# running this is not a precondition for a working build — it is how you retry the
# ones that failed, or rebuild the dictionary after changing the resolver.
#
#   ruby resolve_audio_urls.rb                 # resolve entries with no answer yet
#   ruby resolve_audio_urls.rb --retry-failed  # also retry the ones that came up empty
#   ruby resolve_audio_urls.rb --refresh       # re-resolve everything from scratch

require 'yaml'

require_relative 'lib/audio_dictionary'
require_relative 'lib/audio_resolver'

refresh = ARGV.include?('--refresh')
retry_failed = ARGV.include?('--retry-failed') || refresh

interviews = YAML.load_file('list.yml', aliases: true)['podcast_interviews']
dictionary = AudioDictionary.new
resolver = AudioResolver.new

interviews.each_with_index do |interview, index|
  url = AudioResolver.source_url(interview)
  next unless url

  settled = dictionary.known?(url) && !refresh && (dictionary.resolved?(url) || !retry_failed)
  if settled
    puts "[#{index + 1}/#{interviews.size}] known: #{interview['title']}"
    next
  end

  puts "[#{index + 1}/#{interviews.size}] #{interview['title']}"
  result = resolver.resolve(interview)
  puts "    #{result.reason}" unless result.resolved?

  dictionary.record(interview, result)
  # Saved every iteration so an interrupted run keeps the answers it already paid for.
  dictionary.save
end

puts
puts "#{dictionary.resolved_count}/#{dictionary.entries.size} entries have audio."
