# frozen_string_literal: true

require 'date'
require 'yaml'

require_relative 'audio_resolver'

# The tracked map from an interview's page URL to its audio file.
#
# Failures are recorded too, so a video-only appearance costs one lookup ever
# instead of one per build.
class AudioDictionary
  DEFAULT_PATH = 'audio_urls.yml'

  attr_reader :entries

  def initialize(path: DEFAULT_PATH, entries: nil)
    @path = path
    @entries = entries || read
    @changed = false
  end

  def [](url) = entries[url]

  def known?(url) = entries.key?(url)

  def resolved?(url) = !entries.dig(url, 'audio_url').nil?

  def record(interview, result)
    entries[AudioResolver.source_url(interview)] = {
      'title' => interview['title'],
      'audio_url' => result.audio_url,
      'type' => result.type,
      'length' => result.length,
      'duration' => result.duration,
      'strategy' => result.strategy,
      # Feed matching is a heuristic; keeping the episode title it landed on makes
      # a bad match visible in review instead of only in a listener's player.
      'matched_title' => result.matched_title,
      'reason' => result.reason,
      'resolved_at' => Date.today.to_s
    }.compact

    @changed = true
  end

  def forget(&block)
    removed = entries.size
    entries.reject!(&block)
    @changed ||= entries.size != removed
    removed - entries.size
  end

  def save
    return false unless @changed

    # Sorted so re-resolving an entry moves nothing else in the diff.
    File.write(@path, entries.sort.to_h.to_yaml)
    @changed = false
    true
  end

  def resolved_count = entries.count { |_, entry| entry['audio_url'] }

  private

  def read
    return {} unless File.exist?(@path)

    YAML.load_file(@path) || {}
  end
end
