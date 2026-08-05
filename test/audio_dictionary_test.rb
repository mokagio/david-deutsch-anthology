# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'yaml'

require_relative '../lib/audio_dictionary'

class AudioDictionaryTest < Minitest::Test
  INTERVIEW = { 'title' => 'An interview', 'url' => 'https://example.com/one' }.freeze

  def resolved
    AudioResolver::Result.new(
      audio_url: 'https://example.com/a.mp3', type: 'audio/mpeg', length: 42, strategy: 'feed',
      matched_title: 'An interview — the show'
    )
  end

  def unresolved
    AudioResolver::Result.new(reason: 'no audio source found')
  end

  def in_tmp_dictionary
    Dir.mktmpdir do |dir|
      yield File.join(dir, 'audio_urls.yml')
    end
  end

  def test_records_and_persists_a_resolution
    in_tmp_dictionary do |path|
      dictionary = AudioDictionary.new(path: path)
      dictionary.record(INTERVIEW, resolved)

      assert dictionary.save
      assert_equal 'https://example.com/a.mp3', YAML.load_file(path).dig('https://example.com/one', 'audio_url')
    end
  end

  def test_keeps_the_matched_episode_title_for_review
    dictionary = AudioDictionary.new(entries: {})
    dictionary.record(INTERVIEW, resolved)

    assert_equal 'An interview — the show', dictionary['https://example.com/one']['matched_title']
  end

  def test_a_failure_is_known_but_not_resolved
    dictionary = AudioDictionary.new(entries: {})
    dictionary.record(INTERVIEW, unresolved)

    assert dictionary.known?('https://example.com/one')
    refute dictionary.resolved?('https://example.com/one')
    assert_equal 'no audio source found', dictionary['https://example.com/one']['reason']
  end

  def test_writes_entries_in_a_stable_order
    in_tmp_dictionary do |path|
      dictionary = AudioDictionary.new(path: path, entries: {})
      dictionary.record({ 'title' => 'Second', 'url' => 'https://example.com/b' }, resolved)
      dictionary.record({ 'title' => 'First', 'url' => 'https://example.com/a' }, resolved)
      dictionary.save

      assert_equal %w[https://example.com/a https://example.com/b], YAML.load_file(path).keys
    end
  end

  def test_does_not_rewrite_the_file_when_nothing_changed
    in_tmp_dictionary do |path|
      File.write(path, { 'https://example.com/one' => { 'audio_url' => 'https://example.com/a.mp3' } }.to_yaml)

      refute AudioDictionary.new(path: path).save
    end
  end

  def test_forget_drops_matching_entries
    dictionary = AudioDictionary.new(
      entries: {
        'https://example.com/one' => { 'strategy' => 'feed' },
        'https://example.com/two' => { 'strategy' => 'page' }
      }
    )

    assert_equal 1, dictionary.forget { |_, entry| entry['strategy'] == 'feed' }
    refute dictionary.known?('https://example.com/one')
    assert dictionary.known?('https://example.com/two')
  end
end
