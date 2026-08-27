# frozen_string_literal: true

# Fails the build when the generated feed would not work in a podcast client.
#
#   ruby bin/validate_podcast_rss.rb [path]

require_relative '../lib/feed_validator'

path = ARGV.fetch(0, File.join('public', 'podcast.rss'))
abort "No feed at #{path}" unless File.exist?(path)

errors = FeedValidator.errors(File.read(path))

if errors.empty?
  puts "#{path} is a valid, playable podcast feed."
  exit 0
end

warn "#{path} has #{errors.size} problem(s):"
errors.each { |error| warn "  - #{error}" }
exit 1
