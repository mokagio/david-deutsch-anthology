# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'yaml'

require_relative '../lib/list_writer'

class ListWriterTest < Minitest::Test
  LIST = <<~YAML
    ---

    talks:
      - title: A talk
        url: https://example.com/talk
        audio:
          url: https://example.com/talk.mp3
          type: audio/mpeg
          length: 10163009
        show: &ted
          name: TED Talks Daily
        delivered_date: 2005/07/14

    podcast_interviews:
      - title: An interview # with a comment on it
        url: https://example.com/one
        show: *ted
        published_date: 2024/01/11

      - title: Another interview
        podcast_url: https://example.com/two
        audio:
          url: https://example.com/two.mp3
        show: *ted
        published_date: 2024/02/11
  YAML

  def with_list
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'list.yml')
      File.write(path, LIST)
      yield path
    end
  end

  def addition(entry_url, fields, title: 'An entry')
    { 'title' => title, 'entry_url' => entry_url, 'fields' => fields }
  end

  def entry(path, title)
    YAML.load_file(path, aliases: true).values.flatten.find { |candidate| candidate['title'] == title }
  end

  def test_records_the_runtime_in_the_audio_block
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/two', { 'audio_duration' => 3754 })])

      recorded = entry(path, 'Another interview')

      assert_equal 3754, recorded.dig('audio', 'duration')
      assert_equal 'https://example.com/two.mp3', recorded.dig('audio', 'url')
    end
  end

  def test_records_audio_and_artwork_together
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/one', {
                                          'audio_url' => 'https://example.com/one.mp3',
                                          'audio_type' => 'audio/mpeg',
                                          'audio_length' => 12_345_678,
                                          'image_url' => 'https://example.com/one.jpg'
                                        })])

      recorded = entry(path, 'An interview')

      assert_equal 'https://example.com/one.mp3', recorded.dig('audio', 'url')
      assert_equal 12_345_678, recorded.dig('audio', 'length')
      assert_equal 'https://example.com/one.jpg', recorded['image_url']
    end
  end

  def test_records_the_publication_time_beside_the_date_it_refines
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/two',
                                        { 'published_at' => 'Sun, 11 Feb 2024 09:30:00 +0000' })])

      recorded = entry(path, 'Another interview')

      assert_equal 'Sun, 11 Feb 2024 09:30:00 +0000', recorded['published_at']

      keys = File.readlines(path).map { |line| line.strip.split(':').first }

      assert_equal 'published_at', keys[keys.rindex('published_date') + 1]
    end
  end

  def test_keeps_a_time_out_of_the_media_block
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/two', {
                                          'image_url' => 'https://example.com/two.jpg',
                                          'published_at' => 'Sun, 11 Feb 2024 09:30:00 +0000'
                                        })])

      recorded = entry(path, 'Another interview')

      assert_equal 'https://example.com/two.jpg', recorded['image_url']
      assert_equal 'Sun, 11 Feb 2024 09:30:00 +0000', recorded['published_at']
      assert_nil recorded.dig('audio', 'published_at')
    end
  end

  def test_keeps_the_media_keys_together
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/two', { 'image_url' => 'https://example.com/two.jpg' })])

      keys = File.readlines(path).map { |line| line.strip.split(':').first }

      assert_equal 'image_url', keys[keys.rindex('url') + 1]
    end
  end

  # The sizing pass finds a type and a length for a URL the list already has, so
  # they go into the block that is there rather than starting a second one.
  def test_completes_an_audio_block_the_entry_already_has
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/two', {
                                          'audio_type' => 'audio/mpeg',
                                          'audio_length' => 42_424_242
                                        })])

      recorded = entry(path, 'Another interview')

      assert_equal %w[url type length], recorded['audio'].keys
      assert_equal 'https://example.com/two.mp3', recorded.dig('audio', 'url')
      assert_equal 42_424_242, recorded.dig('audio', 'length')
    end
  end

  # `show` carries a `url` of its own, one level in from the entry's own fields.
  def test_leaves_the_show_block_alone
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/one', {
                                          'audio_url' => 'https://example.com/one.mp3',
                                          'image_url' => 'https://example.com/one.jpg'
                                        })])

      recorded = entry(path, 'An interview')

      assert_equal 'TED Talks Daily', recorded.dig('show', 'name')
      assert_nil recorded.dig('show', 'audio')
    end
  end

  # The anchors and comments are the reason this writes text rather than dumping
  # YAML, so a run that loses them has failed however right the values are.
  def test_leaves_anchors_and_comments_alone
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/one', { 'image_url' => 'https://example.com/one.jpg' })])
      source = File.read(path)

      assert_includes source, '&ted'
      assert_includes source, '*ted'
      assert_includes source, '# with a comment on it'
    end
  end

  # A talk released as an episode carries the same keys an interview does.
  def test_records_against_an_entry_outside_the_interviews
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/talk', { 'image_url' => 'https://example.com/talk.jpg' })])

      assert_equal 'https://example.com/talk.jpg', entry(path, 'A talk')['image_url']
    end
  end

  def test_skips_a_finding_that_matches_no_entry
    with_list do |path|
      applied, skipped = ListWriter.insert(
        path, [addition('https://example.com/nowhere', { 'image_url' => 'https://example.com/nowhere.jpg' })]
      )

      assert_empty applied
      assert_equal 1, skipped.size
      assert_equal LIST, File.read(path)
    end
  end

  def test_writes_nothing_when_the_result_would_not_parse
    with_list do |path|
      broken = [addition('https://example.com/one', { 'image_url' => "one.jpg\n  image_url: two.jpg" })]

      assert_raises(Psych::SyntaxError) { ListWriter.insert(path, broken) }
      assert_equal LIST, File.read(path)
    end
  end

  def test_writes_nothing_when_the_entries_no_longer_add_up
    with_list do |path|
      smuggled = "one.jpg\n\n  - title: Injected\n    url: https://example.com/injected"
      broken = [addition('https://example.com/one', { 'image_url' => smuggled })]

      error = assert_raises(RuntimeError) { ListWriter.insert(path, broken) }

      assert_includes error.message, 'entry count changed'
      assert_equal LIST, File.read(path)
    end
  end
end
