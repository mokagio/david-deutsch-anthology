# frozen_string_literal: true

require 'yaml'

data = YAML.load_file('list.yml', aliases: true)

talks = data['talks'].count
podcast_interviews = data['podcast_interviews'].count
other = data['other'].count

puts "Talks count: #{talks}"
puts "Podcasts count: #{podcast_interviews}"
puts "Other media count: #{other}"
puts '---'
puts "Total: #{talks + podcast_interviews + other}"
