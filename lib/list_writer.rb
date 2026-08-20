# frozen_string_literal: true

require 'yaml'

require_relative 'feed_builder'

# Adds `audio_*` and `image_url` keys to entries in `list.yml`.
#
# Text insertion rather than a YAML dump: `list.yml` uses anchors and comments,
# and Psych renames `&naval` to `&1` and drops every comment on the way out.
module ListWriter
  KEYS = %w[audio_url audio_type audio_length image_url].freeze

  ENTRY_START = /^\s*- /
  MEDIA_KEY = /^\s*(?:audio_(?:url|type|length)|image_url):/
  # Not `audio_url`: one entry's page URL is the mp3 itself, so both keys hold the
  # same value and anchoring on either would be ambiguous.
  ENTRY_URL_KEY = /^[ \t]*(?:podcast_url|youtube_url|url): /

  class << self
    # Each addition is {'entry_url' =>, 'title' =>, 'fields' => {key => value}}. The
    # entry URL is the anchor because it is unique per entry, which `audio_url` is
    # not — two entries can point at the same recording.
    def insert(path, additions)
      lines = File.readlines(path)
      before = counts(File.read(path))
      applied = []
      skipped = []

      additions.each do |addition|
        fields = addition['fields']
        next if fields.empty?

        index = entry_line_index(lines, addition['entry_url'])
        next skipped << [addition['title'], 'no unique line matches the entry URL'] unless index

        indent = lines[index][/\A\s*/]
        at = last_media_line_index(lines, index)
        lines.insert(at + 1, *fields.map { |key, value| "#{indent}#{key}: #{scalar(value)}\n" })
        applied << addition
      end

      source = lines.join
      verify!(source, before, applied)
      File.write(path, source)
      [applied, skipped]
    end

    private

    def entry_line_index(lines, entry_url)
      matches = lines.each_index.select do |index|
        lines[index].match?(ENTRY_URL_KEY) && lines[index].split(': ', 2).last.strip == entry_url
      end

      matches.size == 1 ? matches.first : nil
    end

    # The media keys belong together, so insert after the last one this entry
    # already has; with none, straight after the URL that identifies it.
    def last_media_line_index(lines, index)
      last = index

      ((index + 1)...lines.size).each do |cursor|
        break if lines[cursor].match?(ENTRY_START)

        last = cursor if lines[cursor].match?(MEDIA_KEY)
      end

      last
    end

    # The file's convention is bare scalars; only a `#` would actually need quoting.
    def scalar(value) = value.to_s.include?(' #') ? value.to_s.inspect : value.to_s

    # Across every section the feed publishes: a talk released as an episode gets
    # the same keys an interview does.
    def counts(source)
      list = YAML.load(source, aliases: true)
      entries = FeedBuilder::LABELS.keys.flat_map { |section| list[section] || [] }

      KEYS.to_h { |key| [key, entries.count { |entry| entry[key] }] }
          .merge(entries: entries.size)
    end

    def verify!(source, before, additions)
      after = counts(source)

      raise "entry count changed: #{before[:entries]} -> #{after[:entries]}" unless after[:entries] == before[:entries]

      KEYS.each do |key|
        expected = additions.count { |addition| addition['fields'].key?(key) }
        actual = after[key] - before[key]
        next if actual == expected

        raise "expected #{expected} new #{key} values, found #{actual}"
      end
    end
  end
end
