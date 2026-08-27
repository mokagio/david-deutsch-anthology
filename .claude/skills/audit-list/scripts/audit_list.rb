# frozen_string_literal: true

# Reports on `list.yml`: which links are dead, and which entries have findable
# audio or artwork that the list does not record yet.
#
# With `--write` it records what it finds — the audio URL, the size and type an
# `<enclosure>` needs, and the picture a client shows — so the build never has to
# ask a third-party host anything.
#
#   ruby .claude/skills/audit-list/scripts/audit_list.rb [--links-only|--audio-only] [--json]
#   ruby .claude/skills/audit-list/scripts/audit_list.rb --report <file> --write

require 'json'
require 'net/http'
require 'uri'
require 'yaml'

ROOT = File.expand_path('../../../..', __dir__)
require File.join(ROOT, 'lib', 'media_resolver')
require File.join(ROOT, 'lib', 'enclosure')
require File.join(ROOT, 'lib', 'discovery')
require File.join(ROOT, 'lib', 'duration')
require File.join(ROOT, 'lib', 'feed_builder')
require File.join(ROOT, 'lib', 'list_writer')

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
ignore_path = File.join(ROOT, '.claude', 'skills', 'find-entries', 'ignore.yml')
ignore = Discovery::Ignore.new(File.exist?(ignore_path) ? YAML.load_file(ignore_path) : {})
rejected_entries = data.values.grep(Array).flatten.filter_map do |entry|
  next unless entry.is_a?(Hash)

  reason = ignore.reject_entry(entry)
  { 'title' => entry['title'] || entry['name'], 'reason' => reason } if reason
end

report = {
  'rejected_entries' => rejected_entries,
  'broken_links' => [],
  'unchecked_links' => [],
  'audio_found' => [],
  'audio_missing' => []
}
report = JSON.parse(File.read(from_report)) if from_report
report['rejected_entries'] = rejected_entries
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
  # Whatever the feed publishes is what needs auditing, so a talk carrying podcast
  # audio is checked like an interview.
  publishable = FeedBuilder::LABELS.keys.flat_map { |section| data[section] || [] }

  # Only interviews are worth resolving: a talk without audio was filmed, not aired.
  pending = (data['podcast_interviews'] || []).reject { |interview| interview.dig('audio', 'url') }
  # An enclosure states the file's size and type; recording them here is what keeps
  # the build from having to ask 30-odd third-party hosts on every deploy.
  incomplete = publishable.select { |e| e.dig('audio', 'url') && !(e.dig('audio', 'type') && e.dig('audio', 'length')) }
  recorded = publishable.select { |e| %w[url type length].all? { |key| e.dig('audio', key) } }
  untimed = publishable.select { |e| e.dig('audio', 'url') && !e.dig('audio', 'duration') }
  # A picture the entry inherits from its show already reaches the feed.
  unillustrated = publishable.reject { |e| e['image_url'] || e.dig('show', 'image_url') }

  warn "Looking for audio for #{pending.size} interviews, sizing #{incomplete.size}, " \
       "timing #{untimed.size}, checking #{recorded.size} recorded files, " \
       "illustrating #{unillustrated.size}..."
  resolver = MediaResolver.new(logger: ->(message) { warn message })

  pending.each do |interview|
    warn "  #{interview['title']}"
    result = resolver.resolve(interview)
    entry = { 'title' => interview['title'], 'entry_url' => MediaResolver.source_url(interview) }

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
        'audio_duration' => Duration.seconds(result.duration),
        'strategy' => result.strategy,
        'matched_title' => result.matched_title
      }.compact
    )
  end

  incomplete.each do |interview|
    warn "  sizing #{interview['title']}"
    details = Enclosure.probe(interview.dig('audio', 'url'))

    unless details&.usable?
      report['audio_unreadable'] ||= []
      report['audio_unreadable'] << { 'title' => interview['title'], 'audio_url' => interview.dig('audio', 'url') }
      next
    end

    report['audio_sized'] ||= []
    report['audio_sized'] << {
      'title' => interview['title'],
      'entry_url' => MediaResolver.source_url(interview),
      'audio_type' => details.type,
      'audio_length' => details.length
    }
  end

  # Only a feed or Apple states a runtime; a file found by scraping a page comes
  # with nothing but its bytes, and the entry stays untimed.
  untimed.each do |entry|
    warn "  timing #{entry['title']}"
    result = resolver.resolve(entry)
    seconds = Duration.seconds(result.duration)
    finding = { 'title' => entry['title'], 'entry_url' => MediaResolver.source_url(entry) }

    # A runtime is only this episode's if it describes this episode's file: the
    # resolver reaches other releases of the same conversation, and an edit or a
    # video cut of it does not run for as long.
    same_file = Discovery.normalize_audio_url(result.audio_url.to_s) ==
                Discovery.normalize_audio_url(entry.dig('audio', 'url'))

    unless seconds && same_file
      (report['audio_untimed'] ||= []) << finding.merge(
        'reason' => seconds ? "runtime is #{result.audio_url}'s, not the recorded file's" : 'no source states one'
      )
      next
    end

    (report['audio_timed'] ||= []) << finding.merge(
      { 'audio_duration' => seconds, 'strategy' => result.strategy, 'matched_title' => result.matched_title }.compact
    )
  end

  # Re-measuring what is already recorded is how a two-byte stub and a moved file
  # get noticed. Ad-inserted audio drifts by a fraction of a percent; anything
  # further means the recorded number is wrong.
  recorded.each do |entry|
    warn "  checking #{entry['title']}"
    details = Enclosure.probe(entry.dig('audio', 'url'))

    unless details&.usable?
      report['audio_unreadable'] ||= []
      report['audio_unreadable'] << { 'title' => entry['title'], 'audio_url' => entry.dig('audio', 'url') }
      next
    end

    stored = entry.dig('audio', 'length').to_i
    drift = (details.length - stored).abs * 100.0 / stored
    next if drift <= 1

    report['audio_stale'] ||= []
    report['audio_stale'] << {
      'title' => entry['title'], 'entry_url' => MediaResolver.source_url(entry),
      'recorded' => stored, 'actual' => details.length, 'drift_percent' => drift.round(1)
    }
  end

  unillustrated.each do |entry|
    warn "  illustrating #{entry['title']}"
    artwork = resolver.resolve_artwork(entry)
    finding = { 'title' => entry['title'], 'entry_url' => MediaResolver.source_url(entry) }

    unless artwork.found?
      (report['artwork_missing'] ||= []) << finding.merge('reason' => artwork.reason)
      next
    end

    (report['artwork_found'] ||= []) << finding.merge(
      {
        'image_url' => artwork.image_url,
        'scope' => artwork.scope.to_s,
        'size' => artwork.size,
        'strategy' => artwork.strategy,
        'matched_title' => artwork.matched_title
      }.compact
    )
  end
end

if write
  recorded = FeedBuilder::LABELS.keys.flat_map { |section| data[section] || [] }
                                .to_h { |entry| [MediaResolver.source_url(entry), entry] }

  findings = report['audio_found'] + (report['audio_sized'] || []) +
             (report['audio_timed'] || []) + (report['artwork_found'] || [])

  # Only ever add a key the entry lacks, so applying a report twice is a no-op.
  # Grouped by entry: audio and artwork found in the same run go in together.
  additions = findings.group_by { |finding| finding['entry_url'] }.filter_map do |entry_url, group|
    entry = recorded[entry_url] || {}
    fields = ListWriter::KEYS
             .reject { |_key, path| entry.dig(*path) }
             .to_h { |key, _path| [key, group.filter_map { |finding| finding[key] }.first] }
             .compact

    { 'title' => group.first['title'], 'entry_url' => entry_url, 'fields' => fields } unless fields.empty?
  end

  applied, skipped = ListWriter.insert(LIST_PATH, additions)
  warn "\nUpdated #{applied.size} entries in list.yml."
  skipped.each { |title, reason| warn "  SKIPPED #{title}: #{reason}" }
end

if as_json
  puts JSON.pretty_generate(report)
else
  puts "\n#{report['rejected_entries'].size} entries rejected by discovery rules:"
  report['rejected_entries'].each { |entry| puts "  #{entry['title']} — #{entry['reason']}" }

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

  timed = report['audio_timed'] || []
  unless timed.empty?
    puts "\n#{timed.size} entries with a runtime to add:"
    timed.each { |t| puts "  #{Duration.hms(t['audio_duration'])}  #{t['title']}" }
  end

  unreadable = report['audio_unreadable'] || []
  unless unreadable.empty?
    puts "\n#{unreadable.size} recorded audio files could not be read:"
    unreadable.each { |u| puts "  #{u['title']}\n      #{u['audio_url']}" }
  end

  stale = report['audio_stale'] || []
  unless stale.empty?
    puts "\n#{stale.size} recorded lengths no longer match the file:"
    stale.each { |s| puts "  #{s['title']}\n      recorded #{s['recorded']}, actual #{s['actual']} (#{s['drift_percent']}%)" }
  end

  artwork = report['artwork_found'] || []
  unless artwork.empty?
    puts "\n#{artwork.size} entries with artwork to add:"
    artwork.each do |found|
      measured = found['size'] ? " (#{found['size']})" : ''
      puts "  #{found['title']}\n      #{found['scope']} artwork via #{found['strategy']}#{measured}: #{found['image_url']}"
    end
  end

  puts "\n#{(report['audio_untimed'] || []).size} entries with no runtime found."
  puts "#{report['audio_missing'].size} interviews with no audio found."
  puts "#{(report['artwork_missing'] || []).size} entries with no artwork found."
end
