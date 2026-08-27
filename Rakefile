# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList['test/*_test.rb']
  t.warning = false
end

desc 'Build the static site and the podcast feed'
task :generate do
  ruby 'bin/generate_html.rb'
  ruby 'bin/generate_podcast_rss.rb'
end

desc 'Check the generated feed works in a podcast client'
task :validate do
  ruby 'bin/validate_podcast_rss.rb'
end

desc 'Print entry tallies'
task :count do
  ruby 'bin/count.rb'
end

task default: %i[test generate validate]
