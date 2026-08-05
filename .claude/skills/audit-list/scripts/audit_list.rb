# frozen_string_literal: true

# Reports on `list.yml`: which links are dead, and which podcast interviews have
# findable audio that the list does not record yet.
#
# Reports only — writing the findings back is left to whoever runs this, because
# re-serialising `list.yml` would rename its anchors and drop its comments.
#
#   ruby .claude/skills/audit-list/scripts/audit_list.rb [--links-only|--audio-only] [--json]

require 'json'
require 'net/http'
require 'uri'
require 'yaml'

ROOT = File.expand_path('../../../..', __dir__)
require File.join(ROOT, 'lib', 'audio_resolver')

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

# Inserts `audio_url` beneath the line that already identifies the entry.
#
# Text insertion rather than a YAML dump: `list.yml` uses anchors and comments,
# and Psych renames `&naval` to `&1` and drops every comment on the way out.
module ListWriter
  URL_KEYS = %w[podcast_url url youtube_url].freeze

  class << self
    def insert(path, findings)
      source = File.read(path)
      interviews = YAML.load_file(path, aliases: true)['podcast_interviews']
      before = interviews.size
      added = []
      skipped = []

      # Applying the same report twice is a no-op, not an error.
      recorded = interviews.select { |i| i['audio_url'] }.map { |i| AudioResolver.source_url(i) }
      findings = findings.reject { |finding| recorded.include?(finding['entry_url']) }

      findings.each do |finding|
        line = matching_line(source, finding['entry_url'])
        next skipped << [finding['title'], 'no unique line matches the entry URL'] unless line

        indent = line[/\A\s*/]
        source = source.sub(line, "#{line}#{indent}audio_url: #{quote(finding['audio_url'])}\n")
        added << finding['title']
      end

      verify!(path, source, before, added.size)
      File.write(path, source)
      [added, skipped]
    end

    private

    def matching_line(source, entry_url)
      pattern = /^[ \t]*(?:#{URL_KEYS.join('|')}): #{Regexp.escape(entry_url)}[ \t]*\n/
      matches = source.scan(pattern)
      matches.size == 1 ? source[pattern] : nil
    end

    # The file's own convention is bare URLs; only a `#` would actually need quoting.
    def quote(url) = url.include?(' #') ? url.inspect : url

    def verify!(path, source, expected_entries, expected_additions)
      parsed = YAML.load(source, aliases: true)['podcast_interviews']

      raise "entry count changed: #{expected_entries} -> #{parsed.size}" unless parsed.size == expected_entries

      gained = parsed.count { |interview| interview['audio_url'] }
      had = YAML.load_file(path, aliases: true)['podcast_interviews'].count { |i| i['audio_url'] }
      return if gained - had == expected_additions

      raise "expected #{expected_additions} new audio_url values, found #{gained - had}"
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
  pending = data['podcast_interviews'].reject { |interview| interview['audio_url'] }
  warn "Looking for audio for #{pending.size} interviews..."

  resolver = AudioResolver.new(logger: ->(message) { warn message })

  pending.each do |interview|
    warn "  #{interview['title']}"
    result = resolver.resolve(interview)
    entry = { 'title' => interview['title'], 'entry_url' => AudioResolver.source_url(interview) }

    if result.resolved?
      report['audio_found'] << entry.merge(
        { 'audio_url' => result.audio_url, 'strategy' => result.strategy, 'matched_title' => result.matched_title }.compact
      )
    else
      report['audio_missing'] << entry.merge('reason' => result.reason)
    end
  end
end

if write && !report['audio_found'].empty?
  added, skipped = ListWriter.insert(LIST_PATH, report['audio_found'])
  warn "\nAdded audio_url to #{added.size} entries in list.yml."
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

  puts "\n#{report['audio_missing'].size} interviews with no audio found."
end
