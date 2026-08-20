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
        audio_url: https://example.com/talk.mp3
        audio_type: audio/mpeg
        audio_length: 10163009
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
        audio_url: https://example.com/two.mp3
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

  def test_records_audio_and_artwork_together
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/one', {
                                          'audio_url' => 'https://example.com/one.mp3',
                                          'audio_type' => 'audio/mpeg',
                                          'audio_length' => 12_345_678,
                                          'image_url' => 'https://example.com/one.jpg'
                                        })])

      recorded = entry(path, 'An interview')

      assert_equal 'https://example.com/one.mp3', recorded['audio_url']
      assert_equal 12_345_678, recorded['audio_length']
      assert_equal 'https://example.com/one.jpg', recorded['image_url']
    end
  end

  def test_keeps_the_media_keys_together
    with_list do |path|
      ListWriter.insert(path, [addition('https://example.com/two', { 'image_url' => 'https://example.com/two.jpg' })])

      keys = File.readlines(path).map { |line| line.strip.split(':').first }

      assert_equal 'image_url', keys[keys.rindex('audio_url') + 1]
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
