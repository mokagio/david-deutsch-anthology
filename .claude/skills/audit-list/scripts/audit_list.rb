# frozen_string_literal: true

# Reports on `list.yml`: which links are dead, and which podcast interviews have
# findable audio that the list does not record yet.
#
# With `--write` it records what it finds — the audio URL and the size and type an
# `<enclosure>` needs — so the build never has to ask a third-party host anything.
#
#   ruby .claude/skills/audit-list/scripts/audit_list.rb [--links-only|--audio-only] [--json]
#   ruby .claude/skills/audit-list/scripts/audit_list.rb --report <file> --write

require 'json'
require 'net/http'
require 'uri'
require 'yaml'

ROOT = File.expand_path('../../../..', __dir__)
require File.join(ROOT, 'lib', 'audio_resolver')
require File.join(ROOT, 'lib', 'enclosure')

# Separates "this link is gone" from "I could not tell", because a checker that
# reports the second as the first gets ignored.
class LinkChecker
  Result = Struct.new(:state, :detail, keyword_init: true) do
    def ok? = state == :ok
  end

  YOUTUBE_VIDEO = %r{(?:youtube\.com/watch\?v=|youtu\.be/)}

  HOST_INTERVAL = 0.5

  def initialize
    @last_request_at = {}
  end

  def check(url)
    return check_youtube_video(url) if url.match?(YOUTUBE_VIDEO)

    classify(status(url))
  end

  private

  # oEmbed knows whether a video still exists, but answers 401 when the owner has
  # merely disabled embedding — which the watch page's playability contradicts.
  def check_youtube_video(url)
    code = status("https://www.youtube.com/oembed?format=json&url=#{URI.encode_www_form_component(url)}")
    return Result.new(state: :ok) if code == 200
    return classify(code) unless [401, 403].include?(code)

    playable?(url) ? Result.new(state: :ok, detail: 'embedding disabled') : Result.new(state: :dead, detail: code)
  end

  def playable?(url)
    body = body_of(url)
    body&.include?('"status":"OK"') || false
  end

  def classify(code)
    case code
    when 200 then Result.new(state: :ok)
    when Integer then Result.new(state: :dead, detail: code)
    else Result.new(state: :unreachable, detail: code)
    end
  end

  def status(url, verb: Net::HTTP::Head, retried: false)
    response = request(url, verb)

    # Plenty of hosts refuse HEAD but serve the same URL happily.
    return status(url, verb: Net::HTTP::Get) if verb == Net::HTTP::Head && (!response.is_a?(Integer) || response >= 400)

    if response == 429 && !retried
      sleep 5
      return status(url, verb: verb, retried: true)
    end

    response == 429 ? 'rate limited, not checked' : response
  end

  def request(url, verb, redirects: 5)
    return 'too many redirects' if redirects.negative?

    uri = URI.parse(url)
    return 'not an http URL' unless uri.is_a?(URI::HTTP)

    throttle(uri.host)
    response = Net::HTTP.start(
      uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 20
    ) { |http| http.request(verb.new(uri, 'User-Agent' => HttpClient::USER_AGENT)) }

    if response.is_a?(Net::HTTPRedirection) && response['location']
      return request(URI.join(url, response['location']).to_s, verb, redirects: redirects - 1)
    end

    response.code.to_i
  rescue StandardError => e
    "#{e.class}: #{e.message}"
  end

  def body_of(url)
    HttpClient.get(url)&.body
  end

  # Checking four Naval links back to back earns a 429 that looks like a dead link.
  def throttle(host)
    previous = @last_request_at[host]
    sleep([HOST_INTERVAL - (Time.now - previous), 0].max) if previous
    @last_request_at[host] = Time.now
  end
end

# Adds `audio_*` keys to entries in `list.yml`.
#
# Text insertion rather than a YAML dump: `list.yml` uses anchors and comments,
# and Psych renames `&naval` to `&1` and drops every comment on the way out.
module ListWriter
  ENTRY_START = /^\s*- /
  AUDIO_KEY = /^\s*audio_(?:url|type|length):/
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
        at = last_audio_line_index(lines, index)
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

    # The audio keys belong together, so insert after the last one this entry
    # already has; with none, straight after the URL that identifies it.
    def last_audio_line_index(lines, index)
      last = index

      ((index + 1)...lines.size).each do |cursor|
        break if lines[cursor].match?(ENTRY_START)

        last = cursor if lines[cursor].match?(AUDIO_KEY)
      end

      last
    end

    # The file's convention is bare scalars; only a `#` would actually need quoting.
    def scalar(value) = value.to_s.include?(' #') ? value.to_s.inspect : value.to_s

    def counts(source)
      interviews = YAML.load(source, aliases: true)['podcast_interviews']
      {
        entries: interviews.size,
        'audio_url' => interviews.count { |i| i['audio_url'] },
        'audio_type' => interviews.count { |i| i['audio_type'] },
        'audio_length' => interviews.count { |i| i['audio_length'] }
      }
    end

    def verify!(source, before, additions)
      after = counts(source)

      raise "entry count changed: #{before[:entries]} -> #{after[:entries]}" unless after[:entries] == before[:entries]

      %w[audio_url audio_type audio_length].each do |key|
        expected = additions.count { |addition| addition['fields'].key?(key) }
        actual = after[key] - before[key]
        next if actual == expected

        raise "expected #{expected} new #{key} values, found #{actual}"
      end
    end
  end
end

# Every string under a key ending in `url`, with the entries that point at it.
def collect_urls(data)
  urls = Hash.new { |hash, key| hash[key] = [] }

  data.each do |section, entries|
    next unless entries.is_a?(Array)

    entries.each do |entry|
      label = "#{section}: #{entry['title'] || entry['name'] || '(untitled)'}"
      walk(entry) { |url| urls[url] << label unless urls[url].include?(label) }
    end
  end

  urls
end

def walk(value, &block)
  case value
  when Hash
    value.each do |key, nested|
      block.call(nested) if key.to_s.end_with?('url') && nested.is_a?(String) && nested.start_with?('http')
      walk(nested, &block)
    end
  when Array then value.each { |nested| walk(nested, &block) }
  end
end

mode = ARGV.find { |arg| %w[--links-only --audio-only].include?(arg) }
as_json = ARGV.include?('--json')
write = ARGV.include?('--write')
# Resolving takes minutes, so an earlier run's report can be applied directly.
from_report = ARGV[ARGV.index('--report') + 1] if ARGV.include?('--report')

LIST_PATH = File.join(ROOT, 'list.yml')

data = YAML.load_file(LIST_PATH, aliases: true)
report = { 'broken_links' => [], 'unchecked_links' => [], 'audio_found' => [], 'audio_missing' => [] }
report = JSON.parse(File.read(from_report)) if from_report
mode = '--audio-only' if from_report

unless mode == '--audio-only'
  urls = collect_urls(data)
  warn "Checking #{urls.size} links..."
  checker = LinkChecker.new

  urls.each do |url, labels|
    result = checker.check(url)
    next if result.ok?

    warn "  #{result.state.to_s.upcase} #{result.detail}  #{url}"
    bucket = result.state == :dead ? 'broken_links' : 'unchecked_links'
    report[bucket] << { 'url' => url, 'detail' => result.detail.to_s, 'entries' => labels }
  end
end

unless mode == '--links-only' || from_report
  interviews = data['podcast_interviews']
  pending = interviews.reject { |interview| interview['audio_url'] }
  # An enclosure states the file's size and type; recording them here is what keeps
  # the build from having to ask 34 third-party hosts on every deploy.
  incomplete = interviews.select { |i| i['audio_url'] && !(i['audio_type'] && i['audio_length']) }

  warn "Looking for audio for #{pending.size} interviews, sizing #{incomplete.size} already recorded..."
  resolver = AudioResolver.new(logger: ->(message) { warn message })

  pending.each do |interview|
    warn "  #{interview['title']}"
    result = resolver.resolve(interview)
    entry = { 'title' => interview['title'], 'entry_url' => AudioResolver.source_url(interview) }

    unless result.resolved?
      report['audio_missing'] << entry.merge('reason' => result.reason)
      next
    end

    details = result.length.to_i.positive? ? result : Enclosure.probe(result.audio_url)
    report['audio_found'] << entry.merge(
      {
        'audio_url' => result.audio_url,
        'audio_type' => details&.type,
        'audio_length' => details&.length,
        'strategy' => result.strategy,
        'matched_title' => result.matched_title
      }.compact
    )
  end

  incomplete.each do |interview|
    warn "  sizing #{interview['title']}"
    details = Enclosure.probe(interview['audio_url'])

    unless details&.usable?
      report['audio_unreadable'] ||= []
      report['audio_unreadable'] << { 'title' => interview['title'], 'audio_url' => interview['audio_url'] }
      next
    end

    report['audio_sized'] ||= []
    report['audio_sized'] << {
      'title' => interview['title'],
      'entry_url' => AudioResolver.source_url(interview),
      'audio_type' => details.type,
      'audio_length' => details.length
    }
  end
end

if write
  recorded = data['podcast_interviews'].to_h { |i| [AudioResolver.source_url(i), i] }

  # Only ever add a key the entry lacks, so applying a report twice is a no-op.
  additions = (report['audio_found'] + (report['audio_sized'] || [])).filter_map do |finding|
    interview = recorded[finding['entry_url']] || {}
    fields = %w[audio_url audio_type audio_length]
             .reject { |key| interview[key] }
             .to_h { |key| [key, finding[key]] }
             .compact

    { 'title' => finding['title'], 'entry_url' => finding['entry_url'], 'fields' => fields } unless fields.empty?
  end

  applied, skipped = ListWriter.insert(LIST_PATH, additions)
  warn "\nUpdated #{applied.size} entries in list.yml."
  skipped.each { |title, reason| warn "  SKIPPED #{title}: #{reason}" }
end

if as_json
  puts JSON.pretty_generate(report)
else
  puts "\n#{report['broken_links'].size} dead links:"
  report['broken_links'].each { |l| puts "  #{l['detail']}  #{l['url']}\n      #{l['entries'].join(', ')}" }

  puts "\n#{report['unchecked_links'].size} links I could not verify:"
  report['unchecked_links'].each { |l| puts "  #{l['detail']}  #{l['url']}" }

  puts "\n#{report['audio_found'].size} interviews with audio to add:"
  report['audio_found'].each do |found|
    puts "  #{found['title']}\n      #{found['audio_url']}"
    puts "      matched feed episode: #{found['matched_title']}" if found['matched_title']
  end

  sized = report['audio_sized'] || []
  puts "\n#{sized.size} recorded audio files sized." unless sized.empty?

  unreadable = report['audio_unreadable'] || []
  unless unreadable.empty?
    puts "\n#{unreadable.size} recorded audio files could not be read:"
    unreadable.each { |u| puts "  #{u['title']}\n      #{u['audio_url']}" }
  end

  puts "\n#{report['audio_missing'].size} interviews with no audio found."
end
