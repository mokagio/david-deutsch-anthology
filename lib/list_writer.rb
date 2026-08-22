# frozen_string_literal: true

require 'yaml'

require_relative 'feed_builder'

# Adds the `audio` block and `image_url` to entries in `list.yml`.
#
# Text insertion rather than a YAML dump: `list.yml` uses anchors and comments,
# and Psych renames `&naval` to `&1` and drops every comment on the way out.
module ListWriter
  # The flat name every producer speaks, against where the value lives in the file.
  KEYS = {
    'audio_url' => %w[audio url],
    'audio_type' => %w[audio type],
    'audio_length' => %w[audio length],
    'image_url' => %w[image_url]
  }.freeze

  ENTRY_START = /^\s*- /
  MEDIA_KEY = /^\s*(?:audio|image_url):/
  # Not the audio URL: one entry's page URL is the mp3 itself, so both keys hold
  # the same value and anchoring on either would be ambiguous.
  ENTRY_URL_KEY = /^[ \t]*(?:podcast_url|youtube_url|url): /

  class << self
    # Each addition is {'entry_url' =>, 'title' =>, 'fields' => {key => value}}, the
    # keys being those of `KEYS`. The entry URL is the anchor because it is unique
    # per entry, which the audio URL is not — two entries can share a recording.
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

        place(lines, index, fields)
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

    # The `audio` block first: inserted after `image_url` it would parse the same,
    # but the file's order is url, type, length, picture.
    def place(lines, index, fields)
      nested, flat = fields.partition { |key, _| KEYS.fetch(key).size > 1 }

      nested.group_by { |key, _| KEYS.fetch(key).first }.each do |parent, group|
        insert_nested(lines, index, parent, group.to_h { |key, value| [KEYS.fetch(key).last, value] })
      end

      insert_flat(lines, index, flat.to_h)
    end

    def insert_nested(lines, index, parent, children)
      indent = indent_of(lines[index])
      at = block_line_index(lines, index, parent)

      if at
        lines.insert(last_child_index(lines, at) + 1, *scalars(children, "#{indent}  "))
      else
        lines.insert(anchor_index(lines, index) + 1, "#{indent}#{parent}:\n", *scalars(children, "#{indent}  "))
      end
    end

    def insert_flat(lines, index, fields)
      return if fields.empty?

      lines.insert(anchor_index(lines, index) + 1, *scalars(fields, indent_of(lines[index])))
    end

    def scalars(fields, indent) = fields.map { |key, value| "#{indent}#{key}: #{scalar(value)}\n" }

    def indent_of(line) = line[/\A\s*/]

    # Only the entry's own fields: `show` has a `url` child of its own, and so
    # does `audio`.
    def field_line_indices(lines, index)
      indent = indent_of(lines[index])

      ((index + 1)...lines.size).take_while { |cursor| !lines[cursor].match?(ENTRY_START) }
                                .select { |cursor| indent_of(lines[cursor]) == indent }
    end

    def block_line_index(lines, index, name)
      field_line_indices(lines, index).find { |cursor| lines[cursor].match?(/\A\s*#{name}:\s*$/) }
    end

    def last_child_index(lines, at)
      indent = indent_of(lines[at])

      ((at + 1)...lines.size).take_while { |cursor| indent_of(lines[cursor]).length > indent.length }.last || at
    end

    # The media keys belong together, so insert after the last one this entry
    # already has; with none, straight after the URL that identifies it.
    def anchor_index(lines, index)
      last = field_line_indices(lines, index).select { |cursor| lines[cursor].match?(MEDIA_KEY) }.last
      last ? last_child_index(lines, last) : index
    end

    # The file's convention is bare scalars; only a `#` would actually need quoting.
    def scalar(value) = value.to_s.include?(' #') ? value.to_s.inspect : value.to_s

    # Across every section the feed publishes: a talk released as an episode gets
    # the same keys an interview does.
    def counts(source)
      list = YAML.load(source, aliases: true)
      entries = FeedBuilder::LABELS.keys.flat_map { |section| list[section] || [] }

      KEYS.to_h { |key, path| [key, entries.count { |entry| entry.dig(*path) }] }
          .merge(entries: entries.size)
    end

    def verify!(source, before, additions)
      after = counts(source)

      raise "entry count changed: #{before[:entries]} -> #{after[:entries]}" unless after[:entries] == before[:entries]

      KEYS.each_key do |key|
        expected = additions.count { |addition| addition['fields'].key?(key) }
        actual = after[key] - before[key]
        next if actual == expected

        raise "expected #{expected} new #{key} values, found #{actual}"
      end
    end
  end
end
