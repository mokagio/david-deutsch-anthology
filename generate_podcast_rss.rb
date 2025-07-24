# frozen_string_literal: true

require 'yaml'
require 'erb'
require 'time'
require 'fileutils'

data = YAML.load_file('list.yml', aliases: true)
podcast_interviews = data['podcast_interviews']#.sort { |a, b| Time.parse(a['published_date']) < Time.parse(b['published_date']) }

output_path = File.join('public', 'podcast.rss')
FileUtils.mkdir_p(File.dirname(output_path))

template_path = File.join('templates', 'rss_feed.erb')
template = ERB.new(File.read(template_path), trim_mode: '-')
rss_content = template.result(binding)

File.write(output_path, rss_content)
puts "RSS feed generated successfully: #{output_path}"
